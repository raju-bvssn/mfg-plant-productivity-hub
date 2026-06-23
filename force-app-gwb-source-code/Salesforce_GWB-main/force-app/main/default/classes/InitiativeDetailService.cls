public with sharing class InitiativeDetailService {
    public static final String FORECAST_RT = 'Forecast';
    public static final String ACTUALS_RT = 'Actuals';
    public static final String EFFECTIVE_DATE = 'Effective Date';
    public static final String END_DATE = 'End Date';
    private static final String MISMATCH_MESSAGE = 'Value mismatch. Update the Total Position Adjustment value to match the initiative record.';

    private static final Map<Integer, String> MONTH_PREFIX = new Map<Integer, String>{
        1 => 'Jan', 2 => 'Feb', 3 => 'Mar', 4 => 'Apr', 5 => 'May', 6 => 'Jun',
        7 => 'Jul', 8 => 'Aug', 9 => 'Sep', 10 => 'Oct', 11 => 'Nov', 12 => 'Dec'
    };
    private static final Map<String, String> MONTH_PICKLIST_BY_PREFIX = new Map<String, String>{
        'Jan' => 'January',
        'Feb' => 'February',
        'Mar' => 'March',
        'Apr' => 'April',
        'May' => 'May',
        'Jun' => 'June',
        'Jul' => 'July',
        'Aug' => 'August',
        'Sep' => 'September',
        'Oct' => 'October',
        'Nov' => 'November',
        'Dec' => 'December'
    };

    public static List<InitiativeSectionWrapper> getForecastData(Id initiativeId) {
        Initiative__c initiative = getInitiative(initiativeId);
        return loadSections(initiative, FORECAST_RT);
    }

    public static List<InitiativeSectionWrapper> getActualData(Id initiativeId) {
        Initiative__c initiative = getInitiative(initiativeId);
        List<InitiativeSectionWrapper> sections = loadSections(initiative, ACTUALS_RT);
        hydrateOperations(sections);
        applyActiveOperationFlags(sections, initiative);
        applyForecastDisplayValues(sections, initiative);
        return sections;
    }

    public static List<GwbFunctionWrapper> getAvailablePlantFunctions(Id initiativeId) {
        Initiative__c initiative = getInitiative(initiativeId);
        List<Plant_Function__c> records = [
            SELECT Id, Name, Function_Name__c, Function__r.Name,
                   Plant_Program_Name__c, Program_Code__c, Function_Level__c,
                   Functional_Area__c, Plant_Line__c, Module__c, Shop_Manager_View__c,
                   Crews_Numeric__c,
                   Shift_OR__r.Crews_Numeric__c,
                   Plant_Program__r.Shifts_Def__r.Crews_Numeric__c
            FROM Plant_Function__c
            WHERE Plant__c = :initiative.Plant__c
            AND Status__c = 'Active'
            AND (Shop_Manager_View__c = :initiative.Shop_Manager_View__c OR Shop_Manager_View__c = null)
            ORDER BY Function_Name__c, Name
            LIMIT 200
        ];

        List<GwbFunctionWrapper> wrappers = new List<GwbFunctionWrapper>();
        for (Plant_Function__c record : records) {
            wrappers.add(toFunctionWrapper(record, null, true));
        }
        return wrappers;
    }

    public static List<OperationWrapper> getAvailableOperations(Id initiativeId, Id plantFunctionId) {
        if (plantFunctionId == null) {
            throw friendly('Plant Function Id is required.');
        }
        Initiative__c initiative = getInitiative(initiativeId);
        List<Operation__c> operations = [
            SELECT Id, Operation_Identifier__c, Area__c, Equipment__c, Comment__c,
                   Plant_Function__c, Crews_Numeric__c
            FROM Operation__c
            WHERE Plant__c = :initiative.Plant__c
            AND Plant_Function__c = :plantFunctionId
            AND Active__c = true
            ORDER BY Operation_Identifier__c
            LIMIT 200
        ];

        List<OperationWrapper> wrappers = new List<OperationWrapper>();
        for (Operation__c op : operations) {
            OperationWrapper wrapper = new OperationWrapper();
            wrapper.operationId = op.Id;
            wrapper.id = op.Id;
            wrapper.operationIdentifier = op.Operation_Identifier__c;
            wrapper.area = op.Area__c;
            wrapper.equipment = op.Equipment__c;
            wrapper.comment = op.Comment__c;
            wrappers.add(wrapper);
        }
        return wrappers;
    }

    public static List<InitiativeSectionWrapper> saveForecastData(Id initiativeId, String wrapperJson) {
        Initiative__c initiative = getInitiative(initiativeId);
        List<InitiativeSectionWrapper> sections = parseSections(wrapperJson);
        normalizePermanentSections(sections);
        validateEffectiveTotal(initiative, sections);
        updateInitiativeCalculatedAdjustment(initiative.Id, sections);
        saveWorkbookSections(initiative, sections, FORECAST_RT);
        saveWorkbookSections(initiative, sections, ACTUALS_RT);
        return getForecastData(initiativeId);
    }

    public static List<InitiativeSectionWrapper> saveActualData(Id initiativeId, String wrapperJson) {
        Initiative__c initiative = getInitiative(initiativeId);
        List<InitiativeSectionWrapper> sections = parseSections(wrapperJson);
        normalizeActualOperationTotals(sections);
        normalizePermanentSections(sections);
        validateEffectiveTotal(initiative, sections);
        updateInitiativeCalculatedAdjustment(initiative.Id, sections);
        saveWorkbookSections(initiative, sections, ACTUALS_RT);
        saveAuthorizedDatabaseSections(initiative, sections);
        return getActualData(initiativeId);
    }

    private static List<InitiativeSectionWrapper> loadSections(Initiative__c initiative, String recordTypeDeveloperName) {
        List<InitiativeSectionWrapper> sections = buildEmptySections(initiative);
        Id recordTypeId = getWorkbookRecordTypeId(recordTypeDeveloperName);
        Set<Integer> years = new Set<Integer>();
        for (InitiativeSectionWrapper section : sections) {
            years.add(section.year);
        }

        Set<String> supportedOptions = new Set<String>{ EFFECTIVE_DATE, END_DATE };
        List<Workbook__c> workbooks = [
            SELECT Id, RecordTypeId, Initiative__c, Initiative_Date_Option__c,
                   Plant_Function__c, Plant_Function__r.Name, Plant_Function__r.Function_Name__c,
                   Plant_Function__r.Function__r.Name, Plant_Function__r.Plant_Program_Name__c,
                   Plant_Function__r.Program_Code__c, Plant_Function__r.Function_Level__c,
                   Plant_Function__r.Functional_Area__c, Plant_Function__r.Plant_Line__c,
                   Plant_Function__r.Module__c, Plant_Function__r.Crews_Numeric__c,
                   Plant_Function__r.Shift_OR__r.Crews_Numeric__c,
                   Plant_Function__r.Plant_Program__r.Shifts_Def__r.Crews_Numeric__c,
                   Year__c, Month__c,
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
            WHERE Initiative__c = :initiative.Id
            AND RecordTypeId = :recordTypeId
            AND Year__c IN :years
            AND Initiative_Date_Option__c IN :supportedOptions
            ORDER BY Plant_Function__r.Function_Name__c, Name
        ];

        Map<String, InitiativeSectionWrapper> sectionByOption = new Map<String, InitiativeSectionWrapper>();
        for (InitiativeSectionWrapper section : sections) {
            sectionByOption.put(section.initiativeDateOption, section);
        }
        for (Workbook__c wb : workbooks) {
            InitiativeSectionWrapper section = sectionByOption.get(wb.Initiative_Date_Option__c);
            if (section == null) {
                continue;
            }
            GwbFunctionWrapper row = toFunctionWrapper(wb.Plant_Function__r, wb, section.editable);
            row.crew1 = intValue(wb.get(monthField(section.month, 1)));
            row.crew2 = intValue(wb.get(monthField(section.month, 2)));
            row.crew3 = intValue(wb.get(monthField(section.month, 3)));
            row.total = row.crew1 + row.crew2 + row.crew3;
            section.gwbFunctions.add(row);
        }
        recalcSections(sections);
        return sections;
    }

    private static void saveWorkbookSections(Initiative__c initiative, List<InitiativeSectionWrapper> sections, String recordTypeDeveloperName) {
        Id recordTypeId = getWorkbookRecordTypeId(recordTypeDeveloperName);
        Set<Id> plantFunctionIds = new Set<Id>();
        Set<Integer> years = new Set<Integer>();
        Set<String> options = new Set<String>();
        for (InitiativeSectionWrapper section : sections) {
            years.add(section.year);
            options.add(section.initiativeDateOption);
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (row.plantFunctionId != null) {
                    plantFunctionIds.add(row.plantFunctionId);
                }
            }
        }

        Map<String, Workbook__c> existingByKey = new Map<String, Workbook__c>();
        if (!plantFunctionIds.isEmpty()) {
            for (Workbook__c wb : [
                SELECT Id, RecordTypeId, Initiative__c, Plant_Function__c, Year__c, Initiative_Date_Option__c
                FROM Workbook__c
                WHERE Initiative__c = :initiative.Id
                AND RecordTypeId = :recordTypeId
                AND Plant_Function__c IN :plantFunctionIds
                AND Year__c IN :years
                AND Initiative_Date_Option__c IN :options
            ]) {
                existingByKey.put(workbookKey(wb.Plant_Function__c, intValue(wb.Year__c), wb.Initiative_Date_Option__c), wb);
            }
        }

        List<Workbook__c> upserts = new List<Workbook__c>();
        for (InitiativeSectionWrapper section : sections) {
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (row.plantFunctionId == null) {
                    continue;
                }
                String key = workbookKey(row.plantFunctionId, section.year, section.initiativeDateOption);
                Workbook__c wb = existingByKey.containsKey(key) ? existingByKey.get(key) : new Workbook__c();
                wb.RecordTypeId = recordTypeId;
                wb.Initiative__c = initiative.Id;
                wb.Plant__c = initiative.Plant__c;
                wb.Plant_Function__c = row.plantFunctionId;
                wb.Exclude_From_GWB__c = initiative.Exclude_From_GWB__c;
                wb.Year__c = section.year;
                wb.Month__c = monthPicklistValue(section.month);
                wb.Initiative_Date_Option__c = section.initiativeDateOption;
                wb.put(monthField(section.month, 1), intValue(row.crew1));
                wb.put(monthField(section.month, 2), intValue(row.crew2));
                wb.put(monthField(section.month, 3), intValue(row.crew3));
                upserts.add(wb);
            }
        }
        if (!upserts.isEmpty()) {
            upsert upserts;
        }
    }

    private static void updateInitiativeCalculatedAdjustment(Id initiativeId, List<InitiativeSectionWrapper> sections) {
        if (initiativeId == null || sections == null || sections.isEmpty()) {
            return;
        }
        update new Initiative__c(
            Id = initiativeId,
            Total_Calculated_Adjustment__c = intValue(sections[0].totalAdjustments)
        );
    }

    private static void saveAuthorizedDatabaseSections(Initiative__c initiative, List<InitiativeSectionWrapper> sections) {
        Id actualRecordTypeId = getWorkbookRecordTypeId(ACTUALS_RT);
        Set<Id> plantFunctionIds = new Set<Id>();
        Set<Integer> years = new Set<Integer>();
        Set<String> options = new Set<String>();
        Set<Id> operationIds = new Set<Id>();

        for (InitiativeSectionWrapper section : sections) {
            years.add(section.year);
            options.add(section.initiativeDateOption);
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (row.plantFunctionId != null) {
                    plantFunctionIds.add(row.plantFunctionId);
                }
                for (OperationWrapper op : safeOps(row.operations)) {
                    if (op.operationId != null) {
                        operationIds.add(op.operationId);
                    }
                }
            }
        }
        if (plantFunctionIds.isEmpty() || operationIds.isEmpty()) {
            return;
        }

        Map<String, Workbook__c> workbookByKey = new Map<String, Workbook__c>();
        for (Workbook__c wb : [
            SELECT Id, Plant_Function__c, Year__c, Initiative_Date_Option__c
            FROM Workbook__c
            WHERE Initiative__c = :initiative.Id
            AND RecordTypeId = :actualRecordTypeId
            AND Plant_Function__c IN :plantFunctionIds
            AND Year__c IN :years
            AND Initiative_Date_Option__c IN :options
        ]) {
            workbookByKey.put(workbookKey(wb.Plant_Function__c, intValue(wb.Year__c), wb.Initiative_Date_Option__c), wb);
        }

        Set<Id> workbookIds = new Set<Id>();
        for (Workbook__c wb : workbookByKey.values()) {
            workbookIds.add(wb.Id);
        }
        Map<String, Authorized_Database__c> existingByKey = new Map<String, Authorized_Database__c>();
        if (!workbookIds.isEmpty()) {
            for (Authorized_Database__c authDb : [
                SELECT Id, GWB_Function__c, Operation__c, Plant_Function__c, Year__c
                FROM Authorized_Database__c
                WHERE GWB_Function__c IN :workbookIds
                AND Operation__c IN :operationIds
            ]) {
                existingByKey.put(String.valueOf(authDb.GWB_Function__c) + '|' + String.valueOf(authDb.Operation__c), authDb);
            }
        }

        List<Authorized_Database__c> upserts = new List<Authorized_Database__c>();
        for (InitiativeSectionWrapper section : sections) {
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                Workbook__c wb = workbookByKey.get(workbookKey(row.plantFunctionId, section.year, section.initiativeDateOption));
                if (wb == null) {
                    continue;
                }
                for (OperationWrapper op : safeOps(row.operations)) {
                    if (op.operationId == null) {
                        continue;
                    }
                    String key = String.valueOf(wb.Id) + '|' + String.valueOf(op.operationId);
                    Authorized_Database__c authDb = existingByKey.containsKey(key) ? existingByKey.get(key) : new Authorized_Database__c();
                    authDb.GWB_Function__c = wb.Id;
                    authDb.Operation__c = op.operationId;
                    authDb.Plant__c = initiative.Plant__c;
                    authDb.Plant_Function__c = row.plantFunctionId;
                    authDb.Year__c = section.year;
                    authDb.put(authField(section.month, 1), intValue(op.crew1));
                    authDb.put(authField(section.month, 2), intValue(op.crew2));
                    authDb.put(authField(section.month, 3), intValue(op.crew3));
                    upserts.add(authDb);
                }
            }
        }
        if (!upserts.isEmpty()) {
            upsert upserts;
        }
    }

    private static void hydrateOperations(List<InitiativeSectionWrapper> sections) {
        Set<Id> workbookIds = new Set<Id>();
        Map<Id, GwbFunctionWrapper> rowByWorkbookId = new Map<Id, GwbFunctionWrapper>();
        Map<Id, InitiativeSectionWrapper> sectionByWorkbookId = new Map<Id, InitiativeSectionWrapper>();
        for (InitiativeSectionWrapper section : sections) {
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (row.workbookId != null) {
                    workbookIds.add(row.workbookId);
                    rowByWorkbookId.put(row.workbookId, row);
                    sectionByWorkbookId.put(row.workbookId, section);
                }
            }
        }
        if (workbookIds.isEmpty()) {
            return;
        }

        for (Authorized_Database__c authDb : [
            SELECT Id, GWB_Function__c, Operation__c, Plant_Function__c, Year__c,
                   Operation__r.Operation_Identifier__c,
                   Operation__r.Area__c, Operation__r.Equipment__c, Operation__r.Comment__c,
                   Jan_Crew1__c, Jan_Crew2__c, Jan_Crew3__c,
                   Feb_Crew1__c, Feb_Crew2__c, Feb_Crew3__c,
                   Mar_Crew1__c, Mar_Crew2__c, Mar_Crew3__c,
                   Apr_Crew1__c, Apr_Crew2__c, Apr_Crew3__c,
                   May_Crew1__c, May_Crew2__c, May_Crew3__c,
                   Jun_Crew1__c, Jun_Crew2__c, Jun_Crew3__c,
                   Jul_Crew1__c, Jul_Crew2__c, Jul_Crew3__c,
                   Aug_Crew1__c, Aug_Crew2__c, Aug_Crew3__c,
                   Sep_Crew1__c, Sep_Crew2__c, Sep_Crew3__c,
                   Oct_Crew1__c, Oct_Crew2__c, Oct_Crew3__c,
                   Nov_Crew1__c, Nov_Crew2__c, Nov_Crew3__c,
                   Dec_Crew1__c, Dec_Crew2__c, Dec_Crew3__c
            FROM Authorized_Database__c
            WHERE GWB_Function__c IN :workbookIds
            ORDER BY Operation__r.Operation_Identifier__c
        ]) {
            GwbFunctionWrapper row = rowByWorkbookId.get(authDb.GWB_Function__c);
            InitiativeSectionWrapper section = sectionByWorkbookId.get(authDb.GWB_Function__c);
            if (row == null || section == null) {
                continue;
            }
            OperationWrapper op = new OperationWrapper();
            op.id = authDb.Id;
            op.authorizedDatabaseId = authDb.Id;
            op.operationId = authDb.Operation__c;
            op.operationIdentifier = authDb.Operation__r.Operation_Identifier__c;
            op.area = authDb.Operation__r.Area__c;
            op.equipment = authDb.Operation__r.Equipment__c;
            op.comment = authDb.Operation__r.Comment__c;
            op.crew1 = intValue(authDb.get(authField(section.month, 1)));
            op.crew2 = intValue(authDb.get(authField(section.month, 2)));
            op.crew3 = intValue(authDb.get(authField(section.month, 3)));
            op.total = op.crew1 + op.crew2 + op.crew3;
            row.operations.add(op);
        }
    }

    private static void applyActiveOperationFlags(List<InitiativeSectionWrapper> sections, Initiative__c initiative) {
        Set<Id> plantFunctionIds = new Set<Id>();
        for (InitiativeSectionWrapper section : sections) {
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (row.plantFunctionId != null) {
                    plantFunctionIds.add(row.plantFunctionId);
                }
            }
        }
        if (plantFunctionIds.isEmpty()) {
            return;
        }

        Set<Id> plantFunctionsWithOperations = new Set<Id>();
        for (AggregateResult result : [
            SELECT Plant_Function__c plantFunctionId
            FROM Operation__c
            WHERE Plant__c = :initiative.Plant__c
            AND Plant_Function__c IN :plantFunctionIds
            AND Active__c = true
            GROUP BY Plant_Function__c
        ]) {
            plantFunctionsWithOperations.add((Id) result.get('plantFunctionId'));
        }

        for (InitiativeSectionWrapper section : sections) {
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                row.hasActiveOperations = plantFunctionsWithOperations.contains(row.plantFunctionId);
            }
        }
    }

    private static void applyForecastDisplayValues(List<InitiativeSectionWrapper> sections, Initiative__c initiative) {
        Set<Id> plantFunctionIds = new Set<Id>();
        Set<Integer> years = new Set<Integer>();
        Set<String> options = new Set<String>();
        Map<String, GwbFunctionWrapper> rowByKey = new Map<String, GwbFunctionWrapper>();
        Map<String, InitiativeSectionWrapper> sectionByKey = new Map<String, InitiativeSectionWrapper>();

        for (InitiativeSectionWrapper section : sections) {
            years.add(section.year);
            options.add(section.initiativeDateOption);
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (row.plantFunctionId == null || safeOps(row.operations).isEmpty()) {
                    continue;
                }
                plantFunctionIds.add(row.plantFunctionId);
                String key = workbookKey(row.plantFunctionId, section.year, section.initiativeDateOption);
                rowByKey.put(key, row);
                sectionByKey.put(key, section);
            }
        }
        if (plantFunctionIds.isEmpty()) {
            return;
        }

        Id forecastRecordTypeId = getWorkbookRecordTypeId(FORECAST_RT);
        for (Workbook__c wb : [
            SELECT Id, Plant_Function__c, Year__c, Initiative_Date_Option__c,
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
            WHERE Initiative__c = :initiative.Id
            AND RecordTypeId = :forecastRecordTypeId
            AND Plant_Function__c IN :plantFunctionIds
            AND Year__c IN :years
            AND Initiative_Date_Option__c IN :options
        ]) {
            String key = workbookKey(wb.Plant_Function__c, intValue(wb.Year__c), wb.Initiative_Date_Option__c);
            GwbFunctionWrapper row = rowByKey.get(key);
            InitiativeSectionWrapper section = sectionByKey.get(key);
            if (row == null || section == null) {
                continue;
            }
            row.displayCrew1 = intValue(wb.get(monthField(section.month, 1)));
            row.displayCrew2 = intValue(wb.get(monthField(section.month, 2)));
            row.displayCrew3 = intValue(wb.get(monthField(section.month, 3)));
        }
    }

    private static Initiative__c getInitiative(Id initiativeId) {
        if (initiativeId == null) {
            throw friendly('Initiative Id is required.');
        }
        List<Initiative__c> records = [
            SELECT Id, Name, Plant__c, Plant__r.Name, Shop_Manager_View__c,
                   Classification__c, Driver__c, Headcount_Type__c,
                   Exclude_From_GWB__c, Initiative_Type__c,
                   Effective_Date__c, End_Date__c, Position_Adjustment__c,
                   Parent_Initiative__c, Parent_Initiative__r.Parent_Initiative__c
            FROM Initiative__c
            WHERE Id = :initiativeId
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw friendly('Initiative record was not found.');
        }
        return records[0];
    }

    private static List<InitiativeSectionWrapper> buildEmptySections(Initiative__c initiative) {
        Date effectiveDate = initiative.Effective_Date__c != null ? initiative.Effective_Date__c : Date.today();
        List<InitiativeSectionWrapper> sections = new List<InitiativeSectionWrapper>();
        sections.add(newSection(initiative, 'effective', EFFECTIVE_DATE, effectiveDate, true));
        return sections;
    }

    private static InitiativeSectionWrapper newSection(Initiative__c initiative, String key, String option, Date sectionDate, Boolean editable) {
        InitiativeSectionWrapper section = new InitiativeSectionWrapper();
        section.key = key;
        section.initiativeDateOption = option;
        section.year = sectionDate.year();
        section.month = monthPicklistValue(MONTH_PREFIX.get(sectionDate.month()));
        section.editable = editable;
        section.initiativePositionAdjustment = intValue(initiative.Position_Adjustment__c);
        section.parentInitiativeId = initiative.Parent_Initiative__c;
        section.hasParentInitiative = initiative.Parent_Initiative__c != null;
        section.isContainmentDriver = initiative.Driver__c == 'Containment';
        section.addFunctionsAllowed = initiative.Parent_Initiative__c == null;
        return section;
    }

    private static GwbFunctionWrapper toFunctionWrapper(Plant_Function__c pf, Workbook__c wb, Boolean editable) {
        GwbFunctionWrapper wrapper = new GwbFunctionWrapper();
        if (wb != null) {
            wrapper.workbookId = wb.Id;
        }
        wrapper.plantFunctionId = pf != null ? pf.Id : null;
        wrapper.id = wrapper.workbookId != null ? wrapper.workbookId : wrapper.plantFunctionId;
        wrapper.plantFunctionName = getPlantFunctionName(pf);
        wrapper.programName = pf != null ? pf.Plant_Program_Name__c : null;
        wrapper.programCode = pf != null ? pf.Program_Code__c : null;
        wrapper.functionLevel = pf != null ? pf.Function_Level__c : null;
        wrapper.functionArea = pf != null ? pf.Functional_Area__c : null;
        wrapper.line = pf != null ? pf.Plant_Line__c : null;
        wrapper.module = pf != null ? pf.Module__c : null;
        wrapper.crewEditableCount = deriveCrewCount(pf);
        wrapper.editable = editable;
        return wrapper;
    }

    private static String getPlantFunctionName(Plant_Function__c pf) {
        if (pf == null) {
            return null;
        }
        if (String.isNotBlank(pf.Function_Name__c)) {
            return pf.Function_Name__c;
        }
        if (pf.Function__r != null && String.isNotBlank(pf.Function__r.Name)) {
            return pf.Function__r.Name;
        }
        return pf.Name;
    }

    private static Integer deriveCrewCount(Plant_Function__c pf) {
        Decimal value;
        if (pf != null) {
            value = pf.Crews_Numeric__c;
        }
        if (pf != null && pf.Shift_OR__r != null) {
            value = value == null || value == 0 ? pf.Shift_OR__r.Crews_Numeric__c : value;
        }
        if ((value == null || value == 0) && pf != null && pf.Plant_Program__r != null && pf.Plant_Program__r.Shifts_Def__r != null) {
            value = pf.Plant_Program__r.Shifts_Def__r.Crews_Numeric__c;
        }
        Integer count = value == null ? 1 : Integer.valueOf(value);
        if (count < 1) {
            return 1;
        }
        if (count > 3) {
            return 3;
        }
        return count;
    }

    private static List<InitiativeSectionWrapper> parseSections(String wrapperJson) {
        if (String.isBlank(wrapperJson)) {
            throw friendly('Nothing to save.');
        }
        String trimmed = wrapperJson.trim();
        if (trimmed.startsWith('[')) {
            return (List<InitiativeSectionWrapper>) JSON.deserialize(trimmed, List<InitiativeSectionWrapper>.class);
        }
        SaveRequestWrapper request = (SaveRequestWrapper) JSON.deserialize(trimmed, SaveRequestWrapper.class);
        return request.sections == null ? new List<InitiativeSectionWrapper>() : request.sections;
    }

    private static void normalizeActualOperationTotals(List<InitiativeSectionWrapper> sections) {
        for (InitiativeSectionWrapper section : sections) {
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                if (!safeOps(row.operations).isEmpty()) {
                    row.crew1 = 0;
                    row.crew2 = 0;
                    row.crew3 = 0;
                    for (OperationWrapper op : safeOps(row.operations)) {
                        assertInteger(op.crew1);
                        assertInteger(op.crew2);
                        assertInteger(op.crew3);
                        op.total = intValue(op.crew1) + intValue(op.crew2) + intValue(op.crew3);
                        row.crew1 += intValue(op.crew1);
                        row.crew2 += intValue(op.crew2);
                        row.crew3 += intValue(op.crew3);
                    }
                }
                row.total = intValue(row.crew1) + intValue(row.crew2) + intValue(row.crew3);
            }
        }
        recalcSections(sections);
    }

    private static void normalizePermanentSections(List<InitiativeSectionWrapper> sections) {
        if (sections != null && sections.size() > 1) {
            InitiativeSectionWrapper effective = sections[0];
            sections.clear();
            sections.add(effective);
        }
        recalcSections(sections);
    }

    private static void validateEffectiveTotal(Initiative__c initiative, List<InitiativeSectionWrapper> sections) {
        recalcSections(sections);
        if (sections.isEmpty()) {
            return;
        }
        if (intValue(sections[0].totalAdjustments) != intValue(initiative.Position_Adjustment__c)) {
            throw friendly(MISMATCH_MESSAGE);
        }
    }

    private static void recalcSections(List<InitiativeSectionWrapper> sections) {
        for (InitiativeSectionWrapper section : sections) {
            Integer total = 0;
            for (GwbFunctionWrapper row : section.gwbFunctions) {
                assertInteger(row.crew1);
                assertInteger(row.crew2);
                assertInteger(row.crew3);
                row.total = intValue(row.crew1) + intValue(row.crew2) + intValue(row.crew3);
                total += row.total;
            }
            section.totalAdjustments = total;
        }
    }

    private static List<OperationWrapper> safeOps(List<OperationWrapper> operations) {
        return operations == null ? new List<OperationWrapper>() : operations;
    }

    private static Integer intValue(Object raw) {
        if (raw == null) {
            return 0;
        }
        Decimal value = raw instanceof Decimal ? (Decimal) raw : Decimal.valueOf(String.valueOf(raw));
        Decimal wholeValue = value.setScale(0, System.RoundingMode.DOWN);
        if (value != wholeValue) {
            throw friendly('Only integer crew values are allowed.');
        }
        return Integer.valueOf(wholeValue);
    }

    private static void assertInteger(Object raw) {
        intValue(raw);
    }

    private static String monthField(String month, Integer crew) {
        return normalizeMonth(month) + '_' + String.valueOf(crew) + (crew == 1 ? 'st' : crew == 2 ? 'nd' : 'rd') + '__c';
    }

    private static String authField(String month, Integer crew) {
        return normalizeMonth(month) + '_Crew' + String.valueOf(crew) + '__c';
    }

    private static String normalizeMonth(String month) {
        if (String.isBlank(month)) {
            return MONTH_PREFIX.get(Date.today().month());
        }
        String candidate = month.trim();
        if (candidate.length() > 3) {
            candidate = candidate.substring(0, 3);
        }
        return candidate.substring(0, 1).toUpperCase() + candidate.substring(1).toLowerCase();
    }

    private static String monthPicklistValue(String month) {
        String prefix = normalizeMonth(month);
        return MONTH_PICKLIST_BY_PREFIX.containsKey(prefix) ? MONTH_PICKLIST_BY_PREFIX.get(prefix) : prefix;
    }

    private static String workbookKey(Id plantFunctionId, Integer year, String option) {
        return String.valueOf(plantFunctionId) + '|' + String.valueOf(year) + '|' + option;
    }

    private static Id getWorkbookRecordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Workbook__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        if (info == null) {
            throw friendly('Workbook record type was not found: ' + developerName);
        }
        return info.getRecordTypeId();
    }

    private static AuraHandledException friendly(String message) {
        return new AuraHandledException(message);
    }
}