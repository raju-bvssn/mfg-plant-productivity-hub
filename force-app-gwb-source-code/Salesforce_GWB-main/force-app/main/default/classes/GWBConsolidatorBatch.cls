/**
 * @description       : Batch class that creates/updates GWB_Consolidator__c records when
 *                      Workbook__c records are inserted, when crew month fields
 *                      (Jan_1st__c – Dec_3rd__c) change, or when consolidator grouping keys
 *                      change and old/new grouping seeds are passed from trigger logic.
 *
 *                      One GWB_Consolidator__c record is maintained per unique combination of:
 *                        Plant_Function__c, Year__c, Exclude_From_GWB__c,
 *                        Classification__c, Plant__c, Shop_Manager_View__c, Base_Supp__c,
 *                        RecordType (mapped from the matching Workbook RecordType).
 *
 *                      Month totals are running YTD sums:
 *                        Prev_Dec_Total = Dec_Total__c of the prior-year Consolidator matching
 *                                         Plant_Function__c, Exclude_From_GWB__c, Classification__c,
 *                                         Plant__c, Shop_Manager_View__c, and RecordTypeId.
 *                        Jan_Total  = Prev_Dec_Total + Σ(Jan_1st + Jan_2nd + Jan_3rd) across all
 *                                     grouped Workbooks.
 *                        Feb_Total  = Jan_Total + Σ(Feb adjustments)  … and so on through Dec.
 *
 *                      Strategy: Database.Stateful accumulates per-group monthly sums during
 *                      execute() over chunks of 200 Workbook records, then finish() performs a
 *                      single upsert of all affected Consolidator records.
 *
 * @group             : Plant Management
 * @last modified on  : 05-20-2026
 */
public with sharing class GWBConsolidatorBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * Optional trigger-provided grouping snapshot used to ensure old/new groups
     * are re-evaluated when a workbook moves across grouping keys.
     */
    public class GroupingSeed {
        public Id plantFunctionId;
        public Id plantId;
        public Decimal year;
        public String classification;
        public String shopMgrView;
        public String baseSupp;
        public Boolean excludeFromGwb;
        public Id workbookRecordTypeId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner class: accumulated data for one unique Consolidator group
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    private class GroupData {
        public Id      plantFunctionId;
        public Id      plantId;
        public Decimal year;
        public String  classification;
        public String  shopMgrView;
        public String  baseSupp;
        public Boolean excludeFromGwb;
        public Id      conRecordTypeId;

        public Decimal janSum = 0;
        public Decimal febSum = 0;
        public Decimal marSum = 0;
        public Decimal aprSum = 0;
        public Decimal maySum = 0;
        public Decimal junSum = 0;
        public Decimal julSum = 0;
        public Decimal augSum = 0;
        public Decimal sepSum = 0;
        public Decimal octSum = 0;
        public Decimal novSum = 0;
        public Decimal decSum = 0;

        public GroupData(Workbook__c wb, Id conRecordTypeId) {
            this.plantFunctionId = wb.Plant_Function__c;
            this.plantId         = wb.Plant__c;
            this.year            = wb.Year__c;
            this.classification  = wb.Classification__c;
            this.shopMgrView     = wb.Shop_Mgr_view__c;
            this.baseSupp        = wb.Base_Supp__c;
            this.excludeFromGwb  = wb.Exclude_From_GWB__c;
            this.conRecordTypeId = conRecordTypeId;
        }

        public void accumulate(Workbook__c wb) {
            janSum += d(wb.Jan_1st__c) + d(wb.Jan_2nd__c) + d(wb.Jan_3rd__c);
            febSum += d(wb.Feb_1st__c) + d(wb.Feb_2nd__c) + d(wb.Feb_3rd__c);
            marSum += d(wb.Mar_1st__c) + d(wb.Mar_2nd__c) + d(wb.Mar_3rd__c);
            aprSum += d(wb.Apr_1st__c) + d(wb.Apr_2nd__c) + d(wb.Apr_3rd__c);
            maySum += d(wb.May_1st__c) + d(wb.May_2nd__c) + d(wb.May_3rd__c);
            junSum += d(wb.Jun_1st__c) + d(wb.Jun_2nd__c) + d(wb.Jun_3rd__c);
            julSum += d(wb.Jul_1st__c) + d(wb.Jul_2nd__c) + d(wb.Jul_3rd__c);
            augSum += d(wb.Aug_1st__c) + d(wb.Aug_2nd__c) + d(wb.Aug_3rd__c);
            sepSum += d(wb.Sep_1st__c) + d(wb.Sep_2nd__c) + d(wb.Sep_3rd__c);
            octSum += d(wb.Oct_1st__c) + d(wb.Oct_2nd__c) + d(wb.Oct_3rd__c);
            novSum += d(wb.Nov_1st__c) + d(wb.Nov_2nd__c) + d(wb.Nov_3rd__c);
            decSum += d(wb.Dec_1st__c) + d(wb.Dec_2nd__c) + d(wb.Dec_3rd__c);
        }

        private Decimal d(Decimal v) { return v == null ? 0 : v; }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Serializable state (Database.Stateful persists these across execute() calls)
    // ─────────────────────────────────────────────────────────────────────────

    private Set<Id>      pfIds;
    private Set<Id>      plantIds;
    private Set<Decimal> years;
    private Set<String>  classifs;
    private Set<String>  shopViews;
    private Set<String>  baseSupps;
    private Set<Id>      wbRtIds;

    @TestVisible
    private Map<String, GroupData> groupDataMap;
    private Map<Id, Id>            wbRtToConRtMap;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor — pre-calculates dimension value sets from the changed workbooks
    // plus optional old/new grouping seeds, so start() can build a targeted QueryLocator.
    // ─────────────────────────────────────────────────────────────────────────

    public GWBConsolidatorBatch(Set<Id> changedWorkbookIds) {
        this(changedWorkbookIds, null);
    }

    public GWBConsolidatorBatch(Set<Id> changedWorkbookIds, List<GroupingSeed> additionalGroupingSeeds) {
        groupDataMap   = new Map<String, GroupData>();
        wbRtToConRtMap = new Map<Id, Id>();
        pfIds     = new Set<Id>();
        plantIds  = new Set<Id>();
        years     = new Set<Decimal>();
        classifs  = new Set<String>();
        shopViews = new Set<String>();
        baseSupps = new Set<String>();
        wbRtIds   = new Set<Id>();

        if (changedWorkbookIds != null && !changedWorkbookIds.isEmpty()) {
            for (Workbook__c wb : [
                SELECT Plant_Function__c, Plant__c, Year__c,
                       Classification__c, Shop_Mgr_view__c, Base_Supp__c, RecordTypeId
                FROM Workbook__c
                WHERE Id IN :changedWorkbookIds
                  AND Plant_Function__c != null
                  AND Plant__c != null
                  AND Shop_Mgr_view__c != null
                  AND Classification__c != null
                  AND Base_Supp__c != null
            ]) {
                pfIds.add(wb.Plant_Function__c);
                plantIds.add(wb.Plant__c);
                if (wb.Year__c      != null) years.add(wb.Year__c);
                classifs.add(wb.Classification__c);
                shopViews.add(wb.Shop_Mgr_view__c);
                baseSupps.add(wb.Base_Supp__c);
                if (wb.RecordTypeId != null) wbRtIds.add(wb.RecordTypeId);
            }
        }

        if (additionalGroupingSeeds != null) {
            for (GroupingSeed seed : additionalGroupingSeeds) {
                if (seed == null) continue;
                if (seed.plantFunctionId != null) pfIds.add(seed.plantFunctionId);
                if (seed.plantId != null) plantIds.add(seed.plantId);
                if (seed.year != null) years.add(seed.year);
                if (String.isNotBlank(seed.classification)) classifs.add(seed.classification);
                if (String.isNotBlank(seed.shopMgrView)) shopViews.add(seed.shopMgrView);
                if (String.isNotBlank(seed.baseSupp)) baseSupps.add(seed.baseSupp);
                if (seed.workbookRecordTypeId != null) wbRtIds.add(seed.workbookRecordTypeId);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Batchable interface
    // ─────────────────────────────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        wbRtToConRtMap = buildRecordTypeMapping();

        if (pfIds.isEmpty() || plantIds.isEmpty() || years.isEmpty()
                || classifs.isEmpty() || shopViews.isEmpty()
                || baseSupps.isEmpty() || wbRtIds.isEmpty()) {
            return Database.getQueryLocator([
                SELECT Id FROM Workbook__c WHERE Id = null
            ]);
        }

        return Database.getQueryLocator([
            SELECT Id, Plant_Function__c, Plant__c, Year__c,
                   Classification__c, Shop_Mgr_view__c, Base_Supp__c,
                   Exclude_From_GWB__c, RecordTypeId,
                   Jan_1st__c, Jan_2nd__c, Jan_3rd__c,
                   Feb_1st__c, Feb_2nd__c, Feb_3rd__c,
                   Mar_1st__c, Mar_2nd__c, Mar_3rd__c,
                   Apr_1st__c, Apr_2nd__c, Apr_3rd__c,
                   May_1st__c, May_2nd__c, May_3rd__c,
                   Jun_1st__c, Jun_2nd__c, Jun_3rd__c,
                   Jul_1st__c, Jul_2nd__c, Jul_3rd__c,
                   Aug_1st__c, Aug_2nd__c, Aug_3rd__c,
                   Sep_1st__c, Sep_2nd__c, Sep_3rd__c,
                   Oct_1st__c, Oct_2nd__c, Oct_3rd__c,
                   Nov_1st__c, Nov_2nd__c, Nov_3rd__c,
                   Dec_1st__c, Dec_2nd__c, Dec_3rd__c
            FROM Workbook__c
            WHERE Plant_Function__c IN :pfIds
              AND Plant__c IN :plantIds
              AND Year__c IN :years
              AND Classification__c IN :classifs
              AND Shop_Mgr_view__c IN :shopViews
              AND Base_Supp__c IN :baseSupps
              AND RecordTypeId IN :wbRtIds
        ]);
    }

    /**
     * Accumulates the raw monthly shift sums (1st + 2nd + 3rd shift) for each
     * workbook into its composite-key group entry. All 200-record chunks feed
     * the same stateful groupDataMap so finish() sees the complete picture.
     */
    public void execute(Database.BatchableContext bc, List<Workbook__c> scope) {
        for (Workbook__c wb : scope) {
            if (wb.Plant_Function__c == null || wb.Plant__c == null) continue;

            // Decode Workbook Classification → Consolidator Classification_Group via MDT.
            // ClassificationDecoder uses platform cache (no SOQL consumed).
            // Falls back to the raw value for unmapped classifications.
            String decodedClassif = ClassificationDecoder.toClassificationGroup(wb.Classification__c);
            if (decodedClassif == null) decodedClassif = wb.Classification__c;

            Id     conRtId = wbRtToConRtMap.get(wb.RecordTypeId);
            String key     = buildGroupKey(
                wb.Plant_Function__c, wb.Plant__c, wb.Year__c,
                decodedClassif, wb.Shop_Mgr_view__c, wb.Base_Supp__c,
                wb.Exclude_From_GWB__c, conRtId
            );

            // Single get() avoids double hash lookup — put if absent, then accumulate
            GroupData gd = groupDataMap.get(key);
            if (gd == null) {
                gd = new GroupData(wb, conRtId);
                gd.classification = decodedClassif;
                groupDataMap.put(key, gd);
            }
            gd.accumulate(wb);
        }
    }

    /**
     * After all execute() calls complete, computes YTD totals per group (seeded
     * from the prior-year Consolidator's Dec_Total) and upserts GWB_Consolidator__c.
     */
    public void finish(Database.BatchableContext bc) {
        if (groupDataMap.isEmpty()) return;

        // ── 1. Collect dimension value sets for targeted queries ──────────────
        Set<Id>      finPfIds    = new Set<Id>();
        Set<Id>      finPlantIds = new Set<Id>();
        Set<Decimal> finYears    = new Set<Decimal>();
        Set<String>  finClassifs = new Set<String>();
        Set<String>  finShops    = new Set<String>();
        Set<String>  finBaseSupps= new Set<String>();
        Set<Id>      finConRtIds = new Set<Id>();
        Set<Decimal> prevYearSet = new Set<Decimal>();

        for (GroupData gd : groupDataMap.values()) {
            finPfIds.add(gd.plantFunctionId);
            if (gd.plantId         != null) finPlantIds.add(gd.plantId);
            if (gd.year            != null) {
                finYears.add(gd.year);
                prevYearSet.add(gd.year - 1);
            }
            if (gd.classification  != null) finClassifs.add(gd.classification);
            if (gd.shopMgrView     != null) finShops.add(gd.shopMgrView);
            if (gd.baseSupp        != null) finBaseSupps.add(gd.baseSupp);
            if (gd.conRecordTypeId != null) finConRtIds.add(gd.conRecordTypeId);
        }

        // ── 2. Query existing Consolidator records for this set of groups ─────
        // RecordTypeId filter added so we only match Consolidators of the correct type,
        // avoiding false-positive key collisions across record types.
        Map<String, GWB_Consolidator__c> existingConMap = new Map<String, GWB_Consolidator__c>();
        if (!finPfIds.isEmpty() && !finPlantIds.isEmpty()
                && !finYears.isEmpty() && !finClassifs.isEmpty()
                && !finShops.isEmpty() && !finBaseSupps.isEmpty()) {
            for (GWB_Consolidator__c con : [
                SELECT Id, Plant_Function__c, Plant__c, Year__c,
                       Classification__c, Shop_Manager_View__c, Base_Supp__c,
                       Exclude_From_GWB__c, RecordTypeId
                FROM GWB_Consolidator__c
                WHERE Plant_Function__c IN :finPfIds
                  AND Plant__c IN :finPlantIds
                  AND Year__c IN :finYears
                  AND Classification__c IN :finClassifs
                  AND Shop_Manager_View__c IN :finShops
                  AND Base_Supp__c IN :finBaseSupps
                  AND RecordTypeId IN :finConRtIds
            ]) {
                String key = buildGroupKey(
                    con.Plant_Function__c, con.Plant__c, con.Year__c,
                    con.Classification__c, con.Shop_Manager_View__c, con.Base_Supp__c,
                    con.Exclude_From_GWB__c, con.RecordTypeId
                );
                existingConMap.put(key, con);
            }
        }

        // ── 3. Query prior-year Consolidators for Prev_Dec_Total seed ─────────
        //      Matching fields: Plant_Function__c, Exclude_From_GWB__c,
        //                       Classification__c, Plant__c, Shop_Manager_View__c,
        //                       Base_Supp__c
        //      plus Year__c = current Year__c - 1.
        Map<String, Decimal> prevDecMap = new Map<String, Decimal>();
        if (!finPfIds.isEmpty() && !finPlantIds.isEmpty()
                && !prevYearSet.isEmpty() && !finClassifs.isEmpty()
                && !finShops.isEmpty() && !finBaseSupps.isEmpty()
                && !finConRtIds.isEmpty()) {
            for (GWB_Consolidator__c prevCon : [
                SELECT Plant_Function__c, Plant__c, Year__c,
                       Classification__c, Shop_Manager_View__c, Base_Supp__c,
                       Exclude_From_GWB__c, RecordTypeId, Dec_Total__c
                FROM GWB_Consolidator__c
                WHERE Plant_Function__c IN :finPfIds
                  AND Plant__c IN :finPlantIds
                  AND Year__c IN :prevYearSet
                  AND Classification__c IN :finClassifs
                  AND Shop_Manager_View__c IN :finShops
                  AND Base_Supp__c IN :finBaseSupps
                  AND RecordTypeId IN :finConRtIds
            ]) {
                String  prevKey = buildPrevDecKey(
                    prevCon.Plant_Function__c, prevCon.Plant__c,
                    prevCon.Classification__c, prevCon.Shop_Manager_View__c, prevCon.Base_Supp__c,
                    prevCon.Exclude_From_GWB__c, prevCon.Year__c, prevCon.RecordTypeId
                );
                // Single get() avoids double lookup; accumulate in case multiple prev-year rows match
                Decimal running = prevDecMap.get(prevKey);
                prevDecMap.put(prevKey, (running == null ? 0 : running) +
                    (prevCon.Dec_Total__c == null ? 0 : prevCon.Dec_Total__c));
            }
        }

        // ── 4. Build insert / update lists ────────────────────────────────────
        List<GWB_Consolidator__c> toInsert = new List<GWB_Consolidator__c>();
        List<GWB_Consolidator__c> toUpdate = new List<GWB_Consolidator__c>();

        for (String key : groupDataMap.keySet()) {
            GroupData gd = groupDataMap.get(key);

            String  prevKey = buildPrevDecKey(
                gd.plantFunctionId, gd.plantId,
                gd.classification, gd.shopMgrView, gd.baseSupp,
                gd.excludeFromGwb, gd.year == null ? null : gd.year - 1, gd.conRecordTypeId
            );
            Decimal prevDec = prevDecMap.get(prevKey);
            if (prevDec == null) prevDec = 0;

            // Running YTD sums seeded from prior-year Dec
            Decimal jan = prevDec + gd.janSum;
            Decimal feb = jan     + gd.febSum;
            Decimal mar = feb     + gd.marSum;
            Decimal apr = mar     + gd.aprSum;
            Decimal may = apr     + gd.maySum;
            Decimal jun = may     + gd.junSum;
            Decimal jul = jun     + gd.julSum;
            Decimal aug = jul     + gd.augSum;
            Decimal sep = aug     + gd.sepSum;
            Decimal oct = sep     + gd.octSum;
            Decimal nov = oct     + gd.novSum;
            Decimal dec = nov     + gd.decSum;

            // Single get() avoids double lookup
            GWB_Consolidator__c con = existingConMap.get(key);
            Boolean isNew = (con == null);

            if (isNew) {
                con = new GWB_Consolidator__c(
                    Plant_Function__c    = gd.plantFunctionId,
                    Plant__c             = gd.plantId,
                    Year__c              = gd.year,
                    Classification__c    = gd.classification,
                    Shop_Manager_View__c = gd.shopMgrView,
                    Base_Supp__c         = gd.baseSupp,
                    Exclude_From_GWB__c  = gd.excludeFromGwb == null ? false : gd.excludeFromGwb
                );
                if (gd.conRecordTypeId != null) {
                    con.RecordTypeId = gd.conRecordTypeId;
                }
            }

            con.Prev_Dec_Total__c = prevDec;
            con.Jan_Total__c      = jan;
            con.Feb_Total__c      = feb;
            con.Mar_Total__c      = mar;
            con.Apr_Total__c      = apr;
            con.May_Total__c      = may;
            con.Jun_Total__c      = jun;
            con.Jul_Total__c      = jul;
            con.Aug_Total__c      = aug;
            con.Sep_Total__c      = sep;
            con.Oct_Total__c      = oct;
            con.Nov_Total__c      = nov;
            con.Dec_Total__c      = dec;

            if (isNew) {
                toInsert.add(con);
            } else {
                toUpdate.add(con);
            }
        }

        // ── 5. DML in 200-record chunks ───────────────────────────────────────
        dmlInChunks(toInsert, false);
        dmlInChunks(toUpdate, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Queries RecordType rows for both Workbook__c and GWB_Consolidator__c and
     * builds a map from Workbook RT Id → Consolidator RT Id.
     *
     * DeveloperName mapping:
     *   Workbook Targets  → Consolidator Target
     *   Workbook Actuals  → Consolidator Actual
     *   Workbook Forecast → Consolidator Forecast
     */
    private static Map<Id, Id> buildRecordTypeMapping() {
        Map<String, Id> wbRtByDev  = new Map<String, Id>();
        Map<String, Id> conRtByDev = new Map<String, Id>();

        for (RecordType rt : [
            SELECT Id, DeveloperName, SObjectType
            FROM RecordType
            WHERE SObjectType IN ('Workbook__c', 'GWB_Consolidator__c')
              AND IsActive = true
        ]) {
            if (rt.SObjectType == 'Workbook__c') {
                wbRtByDev.put(rt.DeveloperName, rt.Id);
            } else {
                conRtByDev.put(rt.DeveloperName, rt.Id);
            }
        }

        Map<String, String> wbToConDevName = new Map<String, String>{
            'Targets'  => 'Target',
            'Actuals'  => 'Actual',
            'Forecast' => 'Forecast'
        };

        Map<Id, Id> rtMap = new Map<Id, Id>();
        for (String wbDev : wbToConDevName.keySet()) {
            Id wbRtId  = wbRtByDev.get(wbDev);
            Id conRtId = conRtByDev.get(wbToConDevName.get(wbDev));
            if (wbRtId != null && conRtId != null) {
                rtMap.put(wbRtId, conRtId);
            }
        }
        return rtMap;
    }

    /**
     * Composite key for groupDataMap and existingConMap.
     * Uses the Consolidator's RecordTypeId (post-mapping) so both sides produce
     * an identical string for matching pairs.
     */
    @TestVisible
    private static String buildGroupKey(
        Id plantFunctionId, Id plantId, Decimal year,
        String classification, String shopMgrView, String baseSupp,
        Boolean excludeFromGwb, Id conRecordTypeId
    ) {
        return s(plantFunctionId)  + '|' +
               s(plantId)         + '|' +
               s(year)            + '|' +
               s(classification)  + '|' +
               s(shopMgrView)     + '|' +
               s(baseSupp)        + '|' +
               String.valueOf(excludeFromGwb == null ? false : excludeFromGwb) + '|' +
               s(conRecordTypeId);
    }

    /**
     * Composite key for the prior-year Prev_Dec_Total lookup.
     * Uses the business grouping fields plus Year__c and RecordTypeId.
     */
    @TestVisible
    private static String buildPrevDecKey(
        Id plantFunctionId, Id plantId,
        String classification, String shopMgrView, String baseSupp,
        Boolean excludeFromGwb, Decimal year, Id conRecordTypeId
    ) {
        return s(plantFunctionId) + '|' +
               s(plantId)        + '|' +
               s(classification) + '|' +
               s(shopMgrView)    + '|' +
               s(baseSupp)       + '|' +
               String.valueOf(excludeFromGwb == null ? false : excludeFromGwb) + '|' +
               s(year) + '|' +
               s(conRecordTypeId);
    }

    /** Null-safe toString for composite key segments. */
    private static String s(Object o) {
        return o == null ? '' : String.valueOf(o);
    }

    /**
     * Executes insert or update DML in 200-record chunks (allOrNone=true by default).
     * If any record in a chunk fails the entire chunk's transaction is rolled back.
     * The exception is logged then re-thrown so the batch framework records the
     * failure in AsyncApexJob.NumberOfErrors.
     */
    private static void dmlInChunks(List<GWB_Consolidator__c> records, Boolean isUpdate) {
        if (records == null || records.isEmpty()) return;

        for (Integer i = 0; i < records.size(); i += 200) {
            Integer endIdx = Math.min(i + 200, records.size());
            List<GWB_Consolidator__c> chunk = new List<GWB_Consolidator__c>();
            for (Integer j = i; j < endIdx; j++) {
                chunk.add(records[j]);
            }
            try {
                if (isUpdate) {
                    update chunk;
                } else {
                    insert chunk;
                }
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR,
                    'GWBConsolidatorBatch ' + (isUpdate ? 'update' : 'insert') +
                    ' failed: ' + e.getMessage());
                throw e;
            }
        }
    }
}