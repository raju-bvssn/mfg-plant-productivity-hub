/**
 * @description       : Controller for the Productivity Planning Summary LWC.
 *                      Accepts an AppliedFilterWrapper containing the user's selected
 *                      filter values and queries Workbook__c records accordingly.
 *                      Any filter field whose value is 'All' (or blank/null) is
 *                      excluded from the WHERE clause so no restriction is applied.
 *                      Classification filtering uses ClassificationDecoder to expand
 *                      the group-level filter value (e.g. 'OTS') into all matching
 *                      Workbook__c Classification__c values (e.g. 'Direct OTS',
 *                      'Indirect OTS') via Classification_Decoder__mdt records.
 *                      Returns a list of SummaryRow objects — one per logical display
 *                      row — each carrying row metadata, the plan year, and aggregated
 *                      monthly shift adjustment totals across all matching workbooks.
 * @group             : Plant Management
 * @last modified on  : 05-20-2026
 */
public with sharing class ProdPlanSummaryCntrl {

    private static final String ALL_VALUE = 'All';

    // ─────────────────────────────────────────────────────────────────────────
    // AuraEnabled entry point
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Queries Workbook__c and GWB_Consolidator__c records matching the
     *              supplied filters and returns a list of SummaryRow objects ready for
     *              LWC table rendering. Fields set to 'All' are treated as "no filter".
     * @param  filters  AppliedFilterWrapper carrying the user's active filter selections
     * @return          List<SummaryRow> — one SummaryRow per logical display row
     */
    @AuraEnabled
    public static List<SummaryRow> getSummaryData(AppliedFilterWrapper filters) {
        if (filters == null) {
            return new List<SummaryRow>();
        }

        // ── Workbook query ────────────────────────────────────────────────────
        // Classification uses getClassificationsForGroup() to expand the group-level
        // filter value into all matching raw Workbook Classification__c values.
        // The bind variable :classificationValues must stay in this method's local
        // scope so Database.query() can resolve it.
        List<String> wbConditions = buildWorkbookConditions(filters);
        Set<String> classificationValues = new Set<String>();
        if (isFiltered(filters.classification)) {
            classificationValues = ClassificationDecoder.getClassificationsForGroup(filters.classification);
            if (!classificationValues.isEmpty()) {
                wbConditions.add('Classification__c IN :classificationValues');
            } else {
                wbConditions.add('Classification__c = \'' + String.escapeSingleQuotes(filters.classification) + '\'');
            }
        }
        List<Workbook__c> workbooks = Database.query(buildWorkbookQuery(wbConditions));

        // ── Consolidator query ────────────────────────────────────────────────
        // GWB_Consolidator__c.Classification__c stores the decoded group value
        // (e.g. 'OTS') not the raw workbook value, so toClassificationGroup() is
        // used here for a single equality rather than an IN expansion.
        List<String> conConditions = buildConsolidatorConditions(filters);
        List<GWB_Consolidator__c> consolidators = Database.query(buildConsolidatorQuery(conConditions));

        Integer planYear = isFiltered(filters.year)
            ? Integer.valueOf(filters.year)
            : Date.today().year();

        return buildSummaryRows(planYear, workbooks, consolidators);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static List<String> buildWorkbookConditions(AppliedFilterWrapper filters) {
        List<String> conditions = new List<String>();

        if (isFiltered(filters.plant)) {
            conditions.add('Plant__c = \'' + String.escapeSingleQuotes(filters.plant) + '\'');
        }

        if (isFiltered(filters.shop)) {
            conditions.add('Shop_Mgr_view__c = \'' + String.escapeSingleQuotes(filters.shop) + '\'');
        }

        if (isFiltered(filters.year)) {
            conditions.add('Year__c = ' + Decimal.valueOf(filters.year));
        }

        // Classification is handled in getSummaryData via ClassificationDecoder — not here.

        if (isFiltered(filters.driver)) {
            conditions.add('Driver_New__c = \'' + String.escapeSingleQuotes(filters.driver) + '\'');
        }

        if (isFiltered(filters.baseSupp)) {
            conditions.add('Base_Supp__c = \'' + String.escapeSingleQuotes(filters.baseSupp) + '\'');
        }

        // Exclude_From_GWB__c is a checkbox: map 'Yes' → true, 'No' → false
        if (isFiltered(filters.excludeFromGWB)) {
            Boolean excludeVal = filters.excludeFromGWB == 'Yes';
            conditions.add('Exclude_From_GWB__c = ' + excludeVal);
        }

        // initiativeType and initiativeStatus do not map directly to Workbook__c fields
        // and are intentionally omitted from the WHERE clause here.

        return conditions;
    }

    private static String buildWorkbookQuery(List<String> conditions) {
        String soql =
            'SELECT Id, Year__c, RecordType.DeveloperName, ' +
            'Previous_Year_Workbook__c, Previous_Year_Workbook__r.Dec_1st__c, Previous_Year_Workbook__r.Dec_2nd__c, Previous_Year_Workbook__r.Dec_3rd__c, ' +
            'Jan_1st__c,  Jan_2nd__c,  Jan_3rd__c, ' +
            'Feb_1st__c,  Feb_2nd__c,  Feb_3rd__c, ' +
            'Mar_1st__c,  Mar_2nd__c,  Mar_3rd__c, ' +
            'Apr_1st__c,  Apr_2nd__c,  Apr_3rd__c, ' +
            'May_1st__c,  May_2nd__c,  May_3rd__c, ' +
            'Jun_1st__c,  Jun_2nd__c,  Jun_3rd__c, ' +
            'Jul_1st__c,  Jul_2nd__c,  Jul_3rd__c, ' +
            'Aug_1st__c,  Aug_2nd__c,  Aug_3rd__c, ' +
            'Sep_1st__c,  Sep_2nd__c,  Sep_3rd__c, ' +
            'Oct_1st__c,  Oct_2nd__c,  Oct_3rd__c, ' +
            'Nov_1st__c,  Nov_2nd__c,  Nov_3rd__c, ' +
            'Dec_1st__c,  Dec_2nd__c,  Dec_3rd__c, ' +
            'YTD_Adjustment_Prev_Dec_1st__c, YTD_Adjustment_Prev_Dec_2nd__c, YTD_Adjustment_Prev_Dec_3rd__c, ' +
            'YTD_Adjustment_Jan_1st__c,      YTD_Adjustment_Jan_2nd__c,      YTD_Adjustment_Jan_3rd__c, ' +
            'YTD_Adjustment_Feb_1st__c,      YTD_Adjustment_Feb_2nd__c,      YTD_Adjustment_Feb_3rd__c, ' +
            'YTD_Adjustment_Mar_1st__c,      YTD_Adjustment_Mar_2nd__c,      YTD_Adjustment_Mar_3rd__c, ' +
            'YTD_Adjustment_Apr_1st__c,      YTD_Adjustment_Apr_2nd__c,      YTD_Adjustment_Apr_3rd__c, ' +
            'YTD_Adjustment_May_1st__c,      YTD_Adjustment_May_2nd__c,      YTD_Adjustment_May_3rd__c, ' +
            'YTD_Adjustment_Jun_1st__c,      YTD_Adjustment_Jun_2nd__c,      YTD_Adjustment_Jun_3rd__c, ' +
            'YTD_Adjustment_Jul_1st__c,      YTD_Adjustment_Jul_2nd__c,      YTD_Adjustment_Jul_3rd__c, ' +
            'YTD_Adjustment_Aug_1st__c,      YTD_Adjustment_Aug_2nd__c,      YTD_Adjustment_Aug_3rd__c, ' +
            'YTD_Adjustment_Sep_1st__c,      YTD_Adjustment_Sep_2nd__c,      YTD_Adjustment_Sep_3rd__c, ' +
            'YTD_Adjustment_Oct_1st__c,      YTD_Adjustment_Oct_2nd__c,      YTD_Adjustment_Oct_3rd__c, ' +
            'YTD_Adjustment_Nov_1st__c,      YTD_Adjustment_Nov_2nd__c,      YTD_Adjustment_Nov_3rd__c, ' +
            'YTD_Adjustment_Dec_1st__c,      YTD_Adjustment_Dec_2nd__c,      YTD_Adjustment_Dec_3rd__c ' +
            'FROM Workbook__c';

        if (!conditions.isEmpty()) {
            soql += ' WHERE ' + String.join(conditions, ' AND ');
        }

        soql += ' ORDER BY Year__c DESC, Name ASC';
        return soql;
    }

    /**
     * @description Builds WHERE conditions for GWB_Consolidator__c using the filter values
     *              that have a direct field equivalent on the Consolidator object.
     *              - Classification__c on Consolidator stores the decoded group value
     *                (e.g. 'OTS'), so toClassificationGroup() normalises the filter before
     *                comparison; falls back to a direct match if no mapping exists.
     *              - Shop maps to Shop_Manager_View__c (not Shop_Mgr_view__c).
     *              - driver / initiativeType / initiativeStatus have no Consolidator field
     *                and are omitted.
     */
    private static List<String> buildConsolidatorConditions(AppliedFilterWrapper filters) {
        List<String> conditions = new List<String>();

        if (isFiltered(filters.plant)) {
            conditions.add('Plant__c = \'' + String.escapeSingleQuotes(filters.plant) + '\'');
        }

        if (isFiltered(filters.shop)) {
            conditions.add('Shop_Manager_View__c = \'' + String.escapeSingleQuotes(filters.shop) + '\'');
        }

        if (isFiltered(filters.year)) {
            conditions.add('Year__c = ' + Decimal.valueOf(filters.year));
        }

        if (isFiltered(filters.classification)) {
            String classificationGroup = ClassificationDecoder.toClassificationGroup(filters.classification);
            String classifValue = String.isNotBlank(classificationGroup) ? classificationGroup : filters.classification;
            conditions.add('Classification__c = \'' + String.escapeSingleQuotes(classifValue) + '\'');
        }

        if (isFiltered(filters.baseSupp)) {
            conditions.add('Base_Supp__c = \'' + String.escapeSingleQuotes(filters.baseSupp) + '\'');
        }

        if (isFiltered(filters.excludeFromGWB)) {
            Boolean excludeVal = filters.excludeFromGWB == 'Yes';
            conditions.add('Exclude_From_GWB__c = ' + excludeVal);
        }

        return conditions;
    }

    private static String buildConsolidatorQuery(List<String> conditions) {
        String soql =
            'SELECT Id, RecordType.DeveloperName, Year__c, ' +
            'Plant__c, Plant_Function__c, ' +
            'Classification__c, Shop_Manager_View__c, Base_Supp__c, ' +
            'Exclude_From_GWB__c, ' +
            'Prev_Dec_Total__c, ' +
            'Jan_Total__c, Feb_Total__c, Mar_Total__c, Apr_Total__c, ' +
            'May_Total__c, Jun_Total__c, Jul_Total__c, Aug_Total__c, ' +
            'Sep_Total__c, Oct_Total__c, Nov_Total__c, Dec_Total__c ' +
            'FROM GWB_Consolidator__c';

        if (!conditions.isEmpty()) {
            soql += ' WHERE ' + String.join(conditions, ' AND ');
        }

        soql += ' ORDER BY Year__c DESC';
        return soql;
    }

    /**
     * @description Builds the 9-row skeleton and populates all adjustment columns.
     *
     *  Column index convention:  0 = prevYearDec,  1 = Jan … 12 = Dec
     *  Monthly array index:      0 = Jan … 11 = Dec  (m+1 = calendar month)
     *
     *  Row 4 placement:  primary = currentMonth+1,  secondary = currentMonth+2
     *
     *  previousYearDecAdjustment sources:
     *    Row 1 — Σ Consolidator(Target).Prev_Dec_Total__c
     *    Row 2 — Σ Workbook(Targets).Previous_Year_Workbook__r.Dec_1st/2nd/3rd__c
     *    Row 3 — Σ Workbook(Targets).YTD_Adjustment_Prev_Dec_*__c
     *    Row 4 — null
     *    Row 5 — Σ Consolidator(Actual).Prev_Dec_Total__c
     *    Row 6 — Σ Workbook(Actuals).Previous_Year_Workbook__r.Dec_1st/2nd/3rd__c
     *    Row 7 — Σ Workbook(Actuals).YTD_Adjustment_Prev_Dec_*__c
     *    Row 8 — Row5 − Row1
     *
     *  currentYear*Adjustment (Jan–Dec) sources:
     *    Row 2 — Σ Workbook(Targets).M_1st/2nd/3rd__c
     *    Row 3 — Σ Workbook(Targets).YTD_Adjustment_M_*__c
     *    Row 6 — month < currentMonth → Actuals shift;  month ≥ currentMonth → Forecast shift
     *    Row 7 — month < currentMonth → Actuals YTD;    month ≥ currentMonth → Forecast YTD
     *    Row 1 — cumulative YTD running sum:  prevDec + Σ Row2 values up to month M
     *    Row 5 — cumulative YTD running sum:  prevDec + Σ Row6 values up to month M
     *    Row 4 — null
     *    Row 8 — Row5 − Row1 per month
     */
    private static List<SummaryRow> buildSummaryRows(
            Integer planYear,
            List<Workbook__c> workbooks,
            List<GWB_Consolidator__c> consolidators) {

        Integer currentMonth  = Date.today().month();  // 1=Jan … 12=Dec
        Integer currentYear   = Date.today().year();
        Integer actualCol     = getActualHeaderPlacementColumn(planYear, currentYear, currentMonth);
        Integer forecastStart = getForecastHeaderPlacementColumn(planYear, currentYear, currentMonth);

        List<SummaryRow> rows = new List<SummaryRow>{
            makeRow( 0, true,  planYear,  0,         null,         'Target',             null),
            makeRow( 1, false, planYear,  0,         null,         'Auth Positions YTD',  null),
            makeRow( 2, false, planYear,  0,         null,         'Adjustments',        ''),
            makeRow( 3, false, planYear,  null,      null,         'Adjustments YTD',    ''),
            makeRow( 4, true,  planYear,  actualCol, forecastStart,'← Actuals',          'Forecast →'),
            makeRow( 5, false, planYear,  null,      null,         'Auth Positions YTD',  null),
            makeRow( 6, false, planYear,  null,      null,         'Adjustments',        null),
            makeRow( 7, false, planYear,  null,      null,         'Adjustments YTD',    null),
            makeRow( 8, false, planYear,  null,      null,         'Above/Below Target', null)
        };

        // ── Partition by record type ──────────────────────────────────────────
        List<Workbook__c>         targetWbs   = new List<Workbook__c>();
        List<Workbook__c>         actualsWbs  = new List<Workbook__c>();
        List<Workbook__c>         forecastWbs = new List<Workbook__c>();
        List<GWB_Consolidator__c> targetCons  = new List<GWB_Consolidator__c>();
        List<GWB_Consolidator__c> actualCons  = new List<GWB_Consolidator__c>();

        for (Workbook__c wb : workbooks) {
            String rt = wb.RecordType != null ? wb.RecordType.DeveloperName : null;
            if      (rt == 'Targets')  targetWbs.add(wb);
            else if (rt == 'Actuals')  actualsWbs.add(wb);
            else if (rt == 'Forecast') forecastWbs.add(wb);
        }
        for (GWB_Consolidator__c con : consolidators) {
            String rt = con.RecordType != null ? con.RecordType.DeveloperName : null;
            if      (rt == 'Target') targetCons.add(con);
            else if (rt == 'Actual') actualCons.add(con);
        }

        // ── Pre-compute per-month shift and YTD sums [0=Jan … 11=Dec] ────────
        Decimal[] targetShift   = new Decimal[]{0,0,0,0,0,0,0,0,0,0,0,0};
        Decimal[] targetYtd     = new Decimal[]{0,0,0,0,0,0,0,0,0,0,0,0};
        Decimal[] actualsShift  = new Decimal[]{0,0,0,0,0,0,0,0,0,0,0,0};
        Decimal[] actualsYtd    = new Decimal[]{0,0,0,0,0,0,0,0,0,0,0,0};
        Decimal[] forecastShift = new Decimal[]{0,0,0,0,0,0,0,0,0,0,0,0};
        Decimal[] forecastYtd   = new Decimal[]{0,0,0,0,0,0,0,0,0,0,0,0};

        // YTD_Adjustment_Prev_Dec sums (separate — not part of the Jan–Dec YTD arrays)
        Decimal r2PrevDec = 0;
        Decimal r3PrevDec = 0;
        Decimal r6PrevDec = 0;
        Decimal r7PrevDec = 0;

        for (Workbook__c wb : targetWbs) {
            r2PrevDec += previousYearWorkbookDecTotal(wb);
            r3PrevDec += d(wb.YTD_Adjustment_Prev_Dec_1st__c)
                       + d(wb.YTD_Adjustment_Prev_Dec_2nd__c)
                       + d(wb.YTD_Adjustment_Prev_Dec_3rd__c);
            addToArray(targetShift, monthlyShift(wb));
            addToArray(targetYtd,   monthlyYtdAdj(wb));
        }
        for (Workbook__c wb : actualsWbs) {
            r6PrevDec += previousYearWorkbookDecTotal(wb);
            r7PrevDec += d(wb.YTD_Adjustment_Prev_Dec_1st__c)
                       + d(wb.YTD_Adjustment_Prev_Dec_2nd__c)
                       + d(wb.YTD_Adjustment_Prev_Dec_3rd__c);
            addToArray(actualsShift, monthlyShift(wb));
            addToArray(actualsYtd,   monthlyYtdAdj(wb));
        }
        for (Workbook__c wb : forecastWbs) {
            addToArray(forecastShift, monthlyShift(wb));
            addToArray(forecastYtd,   monthlyYtdAdj(wb));
        }

        // ── Consolidator Prev_Dec_Total sums ─────────────────────────────────
        Decimal r1PrevDec = 0;
        Decimal r5PrevDec = 0;
        for (GWB_Consolidator__c con : targetCons) r1PrevDec += d(con.Prev_Dec_Total__c);
        for (GWB_Consolidator__c con : actualCons)  r5PrevDec += d(con.Prev_Dec_Total__c);

        // ── Assign previousYearDecAdjustment ─────────────────────────────────
        // Row 2 / 6 prev-Dec values come strictly from previous-year Workbook Dec crew values.
        rows[1].previousYearDecAdjustment = r1PrevDec;
        rows[2].previousYearDecAdjustment = r2PrevDec;
        rows[3].previousYearDecAdjustment = r3PrevDec;
        rows[4].previousYearDecAdjustment = null;
        rows[5].previousYearDecAdjustment = r5PrevDec;
        rows[6].previousYearDecAdjustment = r6PrevDec;
        rows[7].previousYearDecAdjustment = r7PrevDec;
        rows[8].previousYearDecAdjustment = r5PrevDec - r1PrevDec;

        // ── Assign currentYear*Adjustment for each month (0=Jan … 11=Dec) ────
        for (Integer m = 0; m < 12; m++) {
            // Row 2 — Target shifts
            setMonthAdj(rows[2], m, targetShift[m]);
            // Row 3 — Target YTD adjustments
            setMonthAdj(rows[3], m, targetYtd[m]);
            // Row 6/7 — split by plan year and month:
            // - past plan year   => all Actuals
            // - future plan year => all Forecast
            // - current plan year => month split (current+future = Forecast)
            Boolean useForecast = shouldUseForecastForMonth(planYear, currentYear, currentMonth, m + 1);
            setMonthAdj(rows[6], m, useForecast ? forecastShift[m] : actualsShift[m]);
            // Row 7 — same split as Row 6
            setMonthAdj(rows[7], m, useForecast ? forecastYtd[m]   : actualsYtd[m]);
            // Row 4 — null (header row)
            setMonthAdj(rows[4], m, null);
        }

        // Row 1 — cumulative YTD: seeds from prevDec, adds Target shift each month
        Decimal r1Run = rows[1].previousYearDecAdjustment;
        for (Integer m = 0; m < 12; m++) {
            r1Run += targetShift[m];
            setMonthAdj(rows[1], m, r1Run);
        }

        // Row 5 — cumulative YTD: seeds from prevDec, adds Row 6 value each month
        Decimal r5Run = rows[5].previousYearDecAdjustment;
        for (Integer m = 0; m < 12; m++) {
            r5Run += getMonthAdj(rows[6], m);
            setMonthAdj(rows[5], m, r5Run);
        }

        // Row 8 — Row5 minus Row1 per month
        for (Integer m = 0; m < 12; m++) {
            setMonthAdj(rows[8], m, getMonthAdj(rows[5], m) - getMonthAdj(rows[1], m));
        }

        return rows;
    }

    // ── Monthly array helpers ─────────────────────────────────────────────────

    /** Returns a 12-element array (0=Jan…11=Dec) of per-shift-period sums. */
    private static Decimal[] monthlyShift(Workbook__c wb) {
        return new Decimal[]{
            d(wb.Jan_1st__c) + d(wb.Jan_2nd__c) + d(wb.Jan_3rd__c),
            d(wb.Feb_1st__c) + d(wb.Feb_2nd__c) + d(wb.Feb_3rd__c),
            d(wb.Mar_1st__c) + d(wb.Mar_2nd__c) + d(wb.Mar_3rd__c),
            d(wb.Apr_1st__c) + d(wb.Apr_2nd__c) + d(wb.Apr_3rd__c),
            d(wb.May_1st__c) + d(wb.May_2nd__c) + d(wb.May_3rd__c),
            d(wb.Jun_1st__c) + d(wb.Jun_2nd__c) + d(wb.Jun_3rd__c),
            d(wb.Jul_1st__c) + d(wb.Jul_2nd__c) + d(wb.Jul_3rd__c),
            d(wb.Aug_1st__c) + d(wb.Aug_2nd__c) + d(wb.Aug_3rd__c),
            d(wb.Sep_1st__c) + d(wb.Sep_2nd__c) + d(wb.Sep_3rd__c),
            d(wb.Oct_1st__c) + d(wb.Oct_2nd__c) + d(wb.Oct_3rd__c),
            d(wb.Nov_1st__c) + d(wb.Nov_2nd__c) + d(wb.Nov_3rd__c),
            d(wb.Dec_1st__c) + d(wb.Dec_2nd__c) + d(wb.Dec_3rd__c)
        };
    }

    /** Returns a 12-element array (0=Jan…11=Dec) of YTD_Adjustment_*__c sums. */
    private static Decimal[] monthlyYtdAdj(Workbook__c wb) {
        return new Decimal[]{
            d(wb.YTD_Adjustment_Jan_1st__c) + d(wb.YTD_Adjustment_Jan_2nd__c) + d(wb.YTD_Adjustment_Jan_3rd__c),
            d(wb.YTD_Adjustment_Feb_1st__c) + d(wb.YTD_Adjustment_Feb_2nd__c) + d(wb.YTD_Adjustment_Feb_3rd__c),
            d(wb.YTD_Adjustment_Mar_1st__c) + d(wb.YTD_Adjustment_Mar_2nd__c) + d(wb.YTD_Adjustment_Mar_3rd__c),
            d(wb.YTD_Adjustment_Apr_1st__c) + d(wb.YTD_Adjustment_Apr_2nd__c) + d(wb.YTD_Adjustment_Apr_3rd__c),
            d(wb.YTD_Adjustment_May_1st__c) + d(wb.YTD_Adjustment_May_2nd__c) + d(wb.YTD_Adjustment_May_3rd__c),
            d(wb.YTD_Adjustment_Jun_1st__c) + d(wb.YTD_Adjustment_Jun_2nd__c) + d(wb.YTD_Adjustment_Jun_3rd__c),
            d(wb.YTD_Adjustment_Jul_1st__c) + d(wb.YTD_Adjustment_Jul_2nd__c) + d(wb.YTD_Adjustment_Jul_3rd__c),
            d(wb.YTD_Adjustment_Aug_1st__c) + d(wb.YTD_Adjustment_Aug_2nd__c) + d(wb.YTD_Adjustment_Aug_3rd__c),
            d(wb.YTD_Adjustment_Sep_1st__c) + d(wb.YTD_Adjustment_Sep_2nd__c) + d(wb.YTD_Adjustment_Sep_3rd__c),
            d(wb.YTD_Adjustment_Oct_1st__c) + d(wb.YTD_Adjustment_Oct_2nd__c) + d(wb.YTD_Adjustment_Oct_3rd__c),
            d(wb.YTD_Adjustment_Nov_1st__c) + d(wb.YTD_Adjustment_Nov_2nd__c) + d(wb.YTD_Adjustment_Nov_3rd__c),
            d(wb.YTD_Adjustment_Dec_1st__c) + d(wb.YTD_Adjustment_Dec_2nd__c) + d(wb.YTD_Adjustment_Dec_3rd__c)
        };
    }

    /** Element-wise addition of source into target (both length 12). */
    private static void addToArray(Decimal[] target, Decimal[] source) {
        for (Integer i = 0; i < 12; i++) {
            target[i] += source[i];
        }
    }

    /**
     * Row 4 header placement (1-indexed relative to full table):
     * - current year: keep existing split around current month.
     * - past year: show Actuals only.
     * - future year: show Forecast only.
     */
    private static Integer getActualHeaderPlacementColumn(Integer planYear, Integer currentYear, Integer currentMonth) {
        if (planYear < currentYear) {
            return 2; // first data column (Prev Dec)
        }
        if (planYear > currentYear) {
            return null; // no Actuals label for all-forecast year
        }
        return currentMonth + 1;
    }

    /**
     * Forecast header start placement (1-indexed relative to full table):
     * - current year: month after current month.
     * - past year: out-of-range so all visible data columns stay in Actuals section.
     * - future year: first data column (all Forecast).
     */
    private static Integer getForecastHeaderPlacementColumn(Integer planYear, Integer currentYear, Integer currentMonth) {
        if (planYear < currentYear) {
            return 15; // beyond row-label + 13 data columns
        }
        if (planYear > currentYear) {
            return 2; // first data column (Prev Dec)
        }
        return currentMonth + 2;
    }

    private static Boolean shouldUseForecastForMonth(
            Integer planYear,
            Integer currentYear,
            Integer currentMonth,
            Integer monthNumber) {
        if (planYear < currentYear) {
            return false;
        }
        if (planYear > currentYear) {
            return true;
        }
        return monthNumber >= currentMonth;
    }

    /**
     * Sets the SummaryRow monthly field identified by 0-based month index m.
     * Accepts null to explicitly clear a header row's value.
     */
    private static void setMonthAdj(SummaryRow row, Integer m, Decimal val) {
        if      (m == 0)  row.currentYearJanAdjustment = val;
        else if (m == 1)  row.currentYearFebAdjustment = val;
        else if (m == 2)  row.currentYearMarAdjustment = val;
        else if (m == 3)  row.currentYearAprAdjustment = val;
        else if (m == 4)  row.currentYearMayAdjustment = val;
        else if (m == 5)  row.currentYearJunAdjustment = val;
        else if (m == 6)  row.currentYearJulAdjustment = val;
        else if (m == 7)  row.currentYearAugAdjustment = val;
        else if (m == 8)  row.currentYearSepAdjustment = val;
        else if (m == 9)  row.currentYearOctAdjustment = val;
        else if (m == 10) row.currentYearNovAdjustment = val;
        else              row.currentYearDecAdjustment = val;
    }

    /** Reads the SummaryRow monthly field identified by 0-based month index m. */
    private static Decimal getMonthAdj(SummaryRow row, Integer m) {
        if      (m == 0)  return row.currentYearJanAdjustment;
        else if (m == 1)  return row.currentYearFebAdjustment;
        else if (m == 2)  return row.currentYearMarAdjustment;
        else if (m == 3)  return row.currentYearAprAdjustment;
        else if (m == 4)  return row.currentYearMayAdjustment;
        else if (m == 5)  return row.currentYearJunAdjustment;
        else if (m == 6)  return row.currentYearJulAdjustment;
        else if (m == 7)  return row.currentYearAugAdjustment;
        else if (m == 8)  return row.currentYearSepAdjustment;
        else if (m == 9)  return row.currentYearOctAdjustment;
        else if (m == 10) return row.currentYearNovAdjustment;
        else              return row.currentYearDecAdjustment;
    }

    /**
     * @description Factory that stamps the structural fields onto a new SummaryRow.
     *              Monthly adjustment fields are intentionally left at their
     *              initialised defaults (0) and will be populated separately.
     */
    private static SummaryRow makeRow(
            Integer idx,
            Boolean isHeader,
            Integer planYear,
            Integer primCol,
            Integer secCol,
            String  primHeader,
            String  secHeader) {

        SummaryRow row = new SummaryRow();
        row.rowIndex                      = idx;
        row.isHeaderRow                   = isHeader;
        row.year                          = planYear;
        row.previousYear                  = planYear - 1;
        row.primaryHeaderPlacementColumn  = primCol;
        row.secondaryHeaderPlacementColumn = secCol;
        row.rowPrimaryHeader              = primHeader;
        row.rowSecondaryHeader            = secHeader;
        return row;
    }

    /**
     * @description Returns true when a filter value should be applied —
     *              i.e. it is non-blank and not the sentinel 'All' value.
     */
    private static Boolean isFiltered(String val) {
        return String.isNotBlank(val) && val != ALL_VALUE;
    }

    private static Decimal d(Decimal val) {
        return val == null ? 0 : val;
    }

    /** Uses previous-year workbook Dec crew values only. */
    private static Decimal previousYearWorkbookDecTotal(Workbook__c wb) {
        if (wb == null || wb.Previous_Year_Workbook__c == null || wb.Previous_Year_Workbook__r == null) {
            return 0;
        }
        return d(wb.Previous_Year_Workbook__r.Dec_1st__c)
             + d(wb.Previous_Year_Workbook__r.Dec_2nd__c)
             + d(wb.Previous_Year_Workbook__r.Dec_3rd__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Mirrors the appliedFilterWrapper JS object from the LWC.
     *              Each property corresponds to a filter dimension from the
     *              global filter panel. A value of 'All' means no restriction.
     */
    public class AppliedFilterWrapper {
        @AuraEnabled public String plant { get; set; }
        @AuraEnabled public String shop { get; set; }
        @AuraEnabled public String year { get; set; }
        @AuraEnabled public String month { get; set; }
        @AuraEnabled public String classification { get; set; }
        @AuraEnabled public String driver { get; set; }
        @AuraEnabled public String baseSupp { get; set; }
        @AuraEnabled public String initiativeType { get; set; }
        @AuraEnabled public String initiativeStatus { get; set; }
        @AuraEnabled public String excludeFromGWB { get; set; }
    }

    /**
     * @description One display row for the summary table.
     *              isHeaderRow=true rows carry label/structure metadata only;
     *              isHeaderRow=false rows carry aggregated monthly adjustment totals.
     *              previousYearDecAdjustment source depends on row semantics:
     *              Consolidator Prev_Dec_Total, previous-year workbook Dec values,
     *              or YTD_Adjustment_Prev_Dec_* aggregates.
     *              currentYear*Adjustment fields are the sum of that month's three
     *              shift fields (1st/2nd/3rd) across all matching workbooks.
     */
    public class SummaryRow {
        @AuraEnabled public Integer rowIndex;
        @AuraEnabled public Boolean isHeaderRow;
        @AuraEnabled public Integer year;
        @AuraEnabled public Integer previousYear;
        @AuraEnabled public Integer  primaryHeaderPlacementColumn;
        @AuraEnabled public Integer  secondaryHeaderPlacementColumn;
        @AuraEnabled public String  rowPrimaryHeader;
        @AuraEnabled public String  rowSecondaryHeader;
        @AuraEnabled public Decimal previousYearDecAdjustment  = 0;
        @AuraEnabled public Decimal currentYearJanAdjustment   = 0;
        @AuraEnabled public Decimal currentYearFebAdjustment   = 0;
        @AuraEnabled public Decimal currentYearMarAdjustment   = 0;
        @AuraEnabled public Decimal currentYearAprAdjustment   = 0;
        @AuraEnabled public Decimal currentYearMayAdjustment   = 0;
        @AuraEnabled public Decimal currentYearJunAdjustment   = 0;
        @AuraEnabled public Decimal currentYearJulAdjustment   = 0;
        @AuraEnabled public Decimal currentYearAugAdjustment   = 0;
        @AuraEnabled public Decimal currentYearSepAdjustment   = 0;
        @AuraEnabled public Decimal currentYearOctAdjustment   = 0;
        @AuraEnabled public Decimal currentYearNovAdjustment   = 0;
        @AuraEnabled public Decimal currentYearDecAdjustment   = 0;
    }
}