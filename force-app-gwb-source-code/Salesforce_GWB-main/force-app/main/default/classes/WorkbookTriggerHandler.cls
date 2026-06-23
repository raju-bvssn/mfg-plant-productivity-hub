/**
 * @description       : Handler class for Workbook__c trigger
 *                      On before insert, auto-populates Previous_Year_Workbook__c by finding a
 *                      matching Workbook__c from the prior year (same RecordType, Plant_Function__c,
 *                      Driver_New__c, Classification__c, Base_Supp__c, and Shop_Mgr_view__c).
 *                      Also enqueues WorkbookYtdAdjustmentBatch to populate YTD_Adjustment_*__c
 *                      running sum fields on insert and on shift field changes during update.
 *                      Prev Dec seed values are written once on insert only.
 *                      Enqueues GWBConsolidatorBatch on insert and on shift/grouping-key changes
 *                      during update to create/update GWB_Consolidator__c aggregation records.
 * @group             : Plant Management
 * @last modified on  : 05-20-2026
 */
public with sharing class WorkbookTriggerHandler {

    private static final String[] SHIFT_FIELDS = new String[]{
        'Jan_1st__c', 'Jan_2nd__c', 'Jan_3rd__c', 'Feb_1st__c', 'Feb_2nd__c', 'Feb_3rd__c',
        'Mar_1st__c', 'Mar_2nd__c', 'Mar_3rd__c', 'Apr_1st__c', 'Apr_2nd__c', 'Apr_3rd__c',
        'May_1st__c', 'May_2nd__c', 'May_3rd__c', 'Jun_1st__c', 'Jun_2nd__c', 'Jun_3rd__c',
        'Jul_1st__c', 'Jul_2nd__c', 'Jul_3rd__c', 'Aug_1st__c', 'Aug_2nd__c', 'Aug_3rd__c',
        'Sep_1st__c', 'Sep_2nd__c', 'Sep_3rd__c', 'Oct_1st__c', 'Oct_2nd__c', 'Oct_3rd__c',
        'Nov_1st__c', 'Nov_2nd__c', 'Nov_3rd__c', 'Dec_1st__c', 'Dec_2nd__c', 'Dec_3rd__c'
    };
    private static final String[] CONSOLIDATOR_GROUPING_FIELDS = new String[]{
        'Plant_Function__c',
        'Plant__c',
        'Year__c',
        'Classification__c',
        'Shop_Mgr_view__c',
        'Base_Supp__c',
        'Exclude_From_GWB__c',
        'RecordTypeId'
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Public entry points
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Handles before insert event for Workbook__c.
     *              Populates Previous_Year_Workbook__c by finding the matching workbook from
     *              Year__c - 1 with the same RecordType, Plant_Function__c, Driver_New__c,
     *              Classification__c, Base_Supp__c, and Shop_Mgr_view__c.
     *              Runs before insert so the after insert batch can immediately use the value.
     * @param newRecords List of Workbook__c records being inserted (mutable in before context)
     */
    public static void handleBeforeInsert(List<Workbook__c> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) return;

        Set<Id> plantFunctionIds = new Set<Id>();
        Set<Decimal> prevYears = new Set<Decimal>();

        for (Workbook__c wb : newRecords) {
            if (wb.Plant_Function__c == null || wb.Year__c == null) continue;
            plantFunctionIds.add(wb.Plant_Function__c);
            prevYears.add(wb.Year__c - 1);
        }

        if (plantFunctionIds.isEmpty()) return;

        // Build a map of prior-year workbooks keyed by the 6 matching fields + year.
        Map<String, Id> prevWorkbookByKey = new Map<String, Id>();
        for (Workbook__c prevWb : [
            SELECT Id, RecordTypeId, Plant_Function__c, Driver_New__c,
                   Classification__c, Base_Supp__c, Shop_Mgr_view__c, Year__c
            FROM Workbook__c
            WHERE Plant_Function__c IN :plantFunctionIds
            AND Year__c IN :prevYears
            ORDER BY CreatedDate DESC
        ]) {
            String key = buildPrevYearKey(
                prevWb.RecordTypeId, prevWb.Plant_Function__c, prevWb.Driver_New__c,
                prevWb.Classification__c, prevWb.Base_Supp__c, prevWb.Shop_Mgr_view__c, prevWb.Year__c
            );
            // First occurrence wins (ordered by CreatedDate DESC so newest is preferred).
            if (!prevWorkbookByKey.containsKey(key)) {
                prevWorkbookByKey.put(key, prevWb.Id);
            }
        }

        for (Workbook__c wb : newRecords) {
            if (wb.Plant_Function__c == null || wb.Year__c == null) continue;
            // Only set if not already explicitly provided.
            if (wb.Previous_Year_Workbook__c != null) continue;
            String key = buildPrevYearKey(
                wb.RecordTypeId, wb.Plant_Function__c, wb.Driver_New__c,
                wb.Classification__c, wb.Base_Supp__c, wb.Shop_Mgr_view__c, wb.Year__c - 1
            );
            if (prevWorkbookByKey.containsKey(key)) {
                wb.Previous_Year_Workbook__c = prevWorkbookByKey.get(key);
            }
        }
    }

    /**
     * @description Handles after insert event for Workbook__c.
     *              Enqueues WorkbookYtdAdjustmentBatch (populatePrevDec=true) to seed
     *              Prev Dec values from the previous year's workbook and compute Jan–Dec running sums.
     *              Also enqueues GWBConsolidatorBatch to create/update GWB_Consolidator__c records.
     * @param newRecords List of inserted Workbook__c records
     */
    public static void handleAfterInsert(List<Workbook__c> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) return;
        Set<Id> ids = new Set<Id>();
        for (Workbook__c wb : newRecords) {
            ids.add(wb.Id);
        }
        Database.executeBatch(new WorkbookYtdAdjustmentBatch(ids, true), 200);
        Database.executeBatch(new GWBConsolidatorBatch(ids), 200);
    }

    /**
     * @description Handles after update event for Workbook__c.
     *              Enqueues WorkbookYtdAdjustmentBatch (populatePrevDec=false) when shift fields
     *              change to recompute YTD Adjustment running sums (Jan–Dec only; Prev Dec untouched).
     *              Enqueues GWBConsolidatorBatch when shift fields or consolidator grouping keys
     *              change; old/new grouping seeds are included so both impacted groups are recalculated.
     * @param newRecords List of updated Workbook__c records
     * @param oldMap Map of old Workbook__c records
     */
    public static void handleAfterUpdate(List<Workbook__c> newRecords, Map<Id, Workbook__c> oldMap) {
        Set<Id> ytdBatchIds = new Set<Id>();
        Set<Id> consolidatorBatchIds = new Set<Id>();
        List<GWBConsolidatorBatch.GroupingSeed> groupingSeeds = new List<GWBConsolidatorBatch.GroupingSeed>();

        for (Workbook__c newRecord : newRecords) {
            Workbook__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord == null) continue;

            Boolean shiftChanged = hasShiftFieldChange(newRecord, oldRecord);
            Boolean groupingChanged = hasConsolidatorGroupingChange(newRecord, oldRecord);

            if (shiftChanged) {
                ytdBatchIds.add(newRecord.Id);
            }
            if (shiftChanged || groupingChanged) {
                consolidatorBatchIds.add(newRecord.Id);
                if (groupingChanged) {
                    groupingSeeds.add(toGroupingSeed(oldRecord));
                    groupingSeeds.add(toGroupingSeed(newRecord));
                }
            }
        }

        if (!ytdBatchIds.isEmpty()) {
            Database.executeBatch(new WorkbookYtdAdjustmentBatch(ytdBatchIds, false), 200);
        }
        if (!consolidatorBatchIds.isEmpty()) {
            Database.executeBatch(new GWBConsolidatorBatch(consolidatorBatchIds, groupingSeeds), 200);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // YTD running sum calculation (in-memory, no DML — called by batch)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Computes all 36 YTD_Adjustment_*__c running sum fields in-memory on a
     *              Workbook__c record. Treats null shift values as 0. Does not touch Prev_Dec fields.
     * @param wb Workbook__c record with shift fields already populated
     */
    public static void calculateYtdOnRecord(Workbook__c wb) {
        Decimal jan1 = dec(wb.Jan_1st__c); Decimal jan2 = dec(wb.Jan_2nd__c); Decimal jan3 = dec(wb.Jan_3rd__c);
        Decimal feb1 = dec(wb.Feb_1st__c); Decimal feb2 = dec(wb.Feb_2nd__c); Decimal feb3 = dec(wb.Feb_3rd__c);
        Decimal mar1 = dec(wb.Mar_1st__c); Decimal mar2 = dec(wb.Mar_2nd__c); Decimal mar3 = dec(wb.Mar_3rd__c);
        Decimal apr1 = dec(wb.Apr_1st__c); Decimal apr2 = dec(wb.Apr_2nd__c); Decimal apr3 = dec(wb.Apr_3rd__c);
        Decimal may1 = dec(wb.May_1st__c); Decimal may2 = dec(wb.May_2nd__c); Decimal may3 = dec(wb.May_3rd__c);
        Decimal jun1 = dec(wb.Jun_1st__c); Decimal jun2 = dec(wb.Jun_2nd__c); Decimal jun3 = dec(wb.Jun_3rd__c);
        Decimal jul1 = dec(wb.Jul_1st__c); Decimal jul2 = dec(wb.Jul_2nd__c); Decimal jul3 = dec(wb.Jul_3rd__c);
        Decimal aug1 = dec(wb.Aug_1st__c); Decimal aug2 = dec(wb.Aug_2nd__c); Decimal aug3 = dec(wb.Aug_3rd__c);
        Decimal sep1 = dec(wb.Sep_1st__c); Decimal sep2 = dec(wb.Sep_2nd__c); Decimal sep3 = dec(wb.Sep_3rd__c);
        Decimal oct1 = dec(wb.Oct_1st__c); Decimal oct2 = dec(wb.Oct_2nd__c); Decimal oct3 = dec(wb.Oct_3rd__c);
        Decimal nov1 = dec(wb.Nov_1st__c); Decimal nov2 = dec(wb.Nov_2nd__c); Decimal nov3 = dec(wb.Nov_3rd__c);
        Decimal dec1 = dec(wb.Dec_1st__c); Decimal dec2 = dec(wb.Dec_2nd__c); Decimal dec3 = dec(wb.Dec_3rd__c);

        // 1st shift running sums
        wb.YTD_Adjustment_Jan_1st__c = jan1;
        wb.YTD_Adjustment_Feb_1st__c = wb.YTD_Adjustment_Jan_1st__c + feb1;
        wb.YTD_Adjustment_Mar_1st__c = wb.YTD_Adjustment_Feb_1st__c + mar1;
        wb.YTD_Adjustment_Apr_1st__c = wb.YTD_Adjustment_Mar_1st__c + apr1;
        wb.YTD_Adjustment_May_1st__c = wb.YTD_Adjustment_Apr_1st__c + may1;
        wb.YTD_Adjustment_Jun_1st__c = wb.YTD_Adjustment_May_1st__c + jun1;
        wb.YTD_Adjustment_Jul_1st__c = wb.YTD_Adjustment_Jun_1st__c + jul1;
        wb.YTD_Adjustment_Aug_1st__c = wb.YTD_Adjustment_Jul_1st__c + aug1;
        wb.YTD_Adjustment_Sep_1st__c = wb.YTD_Adjustment_Aug_1st__c + sep1;
        wb.YTD_Adjustment_Oct_1st__c = wb.YTD_Adjustment_Sep_1st__c + oct1;
        wb.YTD_Adjustment_Nov_1st__c = wb.YTD_Adjustment_Oct_1st__c + nov1;
        wb.YTD_Adjustment_Dec_1st__c = wb.YTD_Adjustment_Nov_1st__c + dec1;

        // 2nd shift running sums
        wb.YTD_Adjustment_Jan_2nd__c = jan2;
        wb.YTD_Adjustment_Feb_2nd__c = wb.YTD_Adjustment_Jan_2nd__c + feb2;
        wb.YTD_Adjustment_Mar_2nd__c = wb.YTD_Adjustment_Feb_2nd__c + mar2;
        wb.YTD_Adjustment_Apr_2nd__c = wb.YTD_Adjustment_Mar_2nd__c + apr2;
        wb.YTD_Adjustment_May_2nd__c = wb.YTD_Adjustment_Apr_2nd__c + may2;
        wb.YTD_Adjustment_Jun_2nd__c = wb.YTD_Adjustment_May_2nd__c + jun2;
        wb.YTD_Adjustment_Jul_2nd__c = wb.YTD_Adjustment_Jun_2nd__c + jul2;
        wb.YTD_Adjustment_Aug_2nd__c = wb.YTD_Adjustment_Jul_2nd__c + aug2;
        wb.YTD_Adjustment_Sep_2nd__c = wb.YTD_Adjustment_Aug_2nd__c + sep2;
        wb.YTD_Adjustment_Oct_2nd__c = wb.YTD_Adjustment_Sep_2nd__c + oct2;
        wb.YTD_Adjustment_Nov_2nd__c = wb.YTD_Adjustment_Oct_2nd__c + nov2;
        wb.YTD_Adjustment_Dec_2nd__c = wb.YTD_Adjustment_Nov_2nd__c + dec2;

        // 3rd shift running sums
        wb.YTD_Adjustment_Jan_3rd__c = jan3;
        wb.YTD_Adjustment_Feb_3rd__c = wb.YTD_Adjustment_Jan_3rd__c + feb3;
        wb.YTD_Adjustment_Mar_3rd__c = wb.YTD_Adjustment_Feb_3rd__c + mar3;
        wb.YTD_Adjustment_Apr_3rd__c = wb.YTD_Adjustment_Mar_3rd__c + apr3;
        wb.YTD_Adjustment_May_3rd__c = wb.YTD_Adjustment_Apr_3rd__c + may3;
        wb.YTD_Adjustment_Jun_3rd__c = wb.YTD_Adjustment_May_3rd__c + jun3;
        wb.YTD_Adjustment_Jul_3rd__c = wb.YTD_Adjustment_Jun_3rd__c + jul3;
        wb.YTD_Adjustment_Aug_3rd__c = wb.YTD_Adjustment_Jul_3rd__c + aug3;
        wb.YTD_Adjustment_Sep_3rd__c = wb.YTD_Adjustment_Aug_3rd__c + sep3;
        wb.YTD_Adjustment_Oct_3rd__c = wb.YTD_Adjustment_Sep_3rd__c + oct3;
        wb.YTD_Adjustment_Nov_3rd__c = wb.YTD_Adjustment_Oct_3rd__c + nov3;
        wb.YTD_Adjustment_Dec_3rd__c = wb.YTD_Adjustment_Nov_3rd__c + dec3;
    }

    /** @description Returns the Decimal value or 0 if null. */
    public static Decimal dec(Decimal val) {
        return val == null ? 0 : val;
    }

    /**
     * @description Builds a composite key from the 6 matching fields + year used to
     *              locate the previous year's workbook. Null values are normalised to
     *              empty string so they match consistently across both sides of the comparison.
     */
    @TestVisible
    private static String buildPrevYearKey(
        Id recordTypeId, Id plantFunctionId, String driver,
        String classification, String baseSupp, String shopMgrView, Decimal year
    ) {
        return (recordTypeId == null ? '' : String.valueOf(recordTypeId)) + '|' +
               (plantFunctionId == null ? '' : String.valueOf(plantFunctionId)) + '|' +
               (driver == null ? '' : driver) + '|' +
               (classification == null ? '' : classification) + '|' +
               (baseSupp == null ? '' : baseSupp) + '|' +
               (shopMgrView == null ? '' : shopMgrView) + '|' +
               (year == null ? '' : String.valueOf(year));
    }

    /**
     * @description Returns true if any shift field (Jan_1st__c through Dec_3rd__c) changed.
     */
    private static Boolean hasShiftFieldChange(Workbook__c current, Workbook__c prior) {
        if (current == null || prior == null) return false;
        for (String f : SHIFT_FIELDS) {
            Decimal nowVal = (Decimal)current.get(f);
            Decimal oldVal = (Decimal)prior.get(f);
            if ((nowVal == null ? 0 : nowVal) != (oldVal == null ? 0 : oldVal)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Returns true if any consolidator grouping field changed.
     */
    private static Boolean hasConsolidatorGroupingChange(Workbook__c current, Workbook__c prior) {
        if (current == null || prior == null) return false;
        for (String f : CONSOLIDATOR_GROUPING_FIELDS) {
            Object nowVal = current.get(f);
            Object oldVal = prior.get(f);
            String nowAsString = nowVal == null ? '' : String.valueOf(nowVal);
            String oldAsString = oldVal == null ? '' : String.valueOf(oldVal);
            if (nowAsString != oldAsString) {
                return true;
            }
        }
        return false;
    }

    private static GWBConsolidatorBatch.GroupingSeed toGroupingSeed(Workbook__c wb) {
        GWBConsolidatorBatch.GroupingSeed seed = new GWBConsolidatorBatch.GroupingSeed();
        seed.plantFunctionId = wb.Plant_Function__c;
        seed.plantId = wb.Plant__c;
        seed.year = wb.Year__c;
        seed.classification = wb.Classification__c;
        seed.shopMgrView = wb.Shop_Mgr_view__c;
        seed.baseSupp = wb.Base_Supp__c;
        seed.excludeFromGwb = wb.Exclude_From_GWB__c;
        seed.workbookRecordTypeId = wb.RecordTypeId;
        return seed;
    }

}