public with sharing class GwbTargetWorkbenchController {
    private static final String GENERIC_COMMENT_ERROR = 'Unable to save the comment right now. Please try again or contact your System Administrator.';
    private static final String PUBLISHED_STATUS = 'Published';
    private static final String LOCKED_STATUS = 'Locked';
    private static final String DRAFT_STATUS = 'Draft';
    private static final String PLANT_REVIEW_STATUS = 'Plant Review';
    private static final String PLANT_REVIEW_COMPLETE_STATUS = 'Plant Review Complete';
    private static final String PLANT_ADMIN_PERMISSION = 'Plant_Admin';
    private static final String INDUSTRIAL_ENGINEER_PERMISSION = 'Industrial_Engineer';
    private static final String PLANT_VIEWER_PERMISSION = 'Plant_Viewer_ReadOnly';
    private static final String TOTAL_MANPOWER_PARAMETER = 'Total Manpower';
    private static final String TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER = 'Total Manpower (Include Target Changes)';
    private static final String PREVIOUS_YE_APPROVED_TARGET_CHANGES_PARAMETER = 'Previous YE Approved Target Changes';
    private static final String LEGACY_APPROVED_TARGET_PARAMETER = 'Approved Target';
    private static final String LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER = 'Advanced Target Changes';
    private static final String PRODUCTIVITY_PERCENT_PARAMETER = '% Prod.';
    private static final String ADDITIONAL_ST_HOURS_PARAMETER = 'Additional Straight Time Hours';
    private static final String COMBINED_ABSENCE_PARAMETER = 'Absenteeism % + Summer VRO %';
    private static final String ST_HOURS_INCLUDE_ADDITIONAL_ST_PARAMETER = 'ST Hours (inc. Add\'l ST Hours)';
    private static final String NSOT_HOURS_PARAMETER = 'NSOT Hours';
    private static final String CATEGORY_OP_PLAN = 'Op Plan';
    private static final String CATEGORY_HEADCOUNT = 'Headcount';
    private static final String CATEGORY_HOURS = 'Hours';
    private static final String SECTION_SCHEDULED_VOLUME = 'Op Plan';
    private static final String SECTION_MANPOWER = 'Headcount';
    private static final String SECTION_HOURS = 'Hours';
    private static final String LEGACY_SECTION_SCHEDULED_VOLUME = 'Scheduled_Volume';
    private static final String LEGACY_SECTION_MANPOWER = 'Manpower';
    private static final String VALUE_TYPE_VALUE = 'Value';
    private static final String VALUE_TYPE_TOTAL = 'Total';
    private static final Set<String> CUMULATIVE_AVERAGE_HC_FAMILIES = new Set<String>{
        'productivity',
        'arc',
        'lms',
        'op plan',
        'vacation replacement',
        'content',
        'sourcing',
        'launch',
        'mfg opt',
        'other/excess'
    };
    private static final Set<String> ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS = new Set<String>{
        'astadj-ots', 'astadj-skilled', 'astadj-salaried'
    };
    @TestVisible private static Boolean plantAdminPermissionOverride;
    @TestVisible private static String currentUserPersonaOverride;
    private static final List<String> MONTH_KEYS = new List<String>{
        'prevDec', 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
    };
    private static final Map<String, String> NUMBER_FIELDS = new Map<String, String>{
        'prevDec' => 'Prev_Dec_Number__c',
        'jan' => 'Jan_Number__c',
        'feb' => 'Feb_Number__c',
        'mar' => 'Mar_Number__c',
        'apr' => 'Apr_Number__c',
        'may' => 'May_Number__c',
        'jun' => 'Jun_Number__c',
        'jul' => 'Jul_Number__c',
        'aug' => 'Aug_Number__c',
        'sep' => 'Sep_Number__c',
        'oct' => 'Oct_Number__c',
        'nov' => 'Nov_Number__c',
        'dec' => 'Dec_Number__c'
    };
    private static final Map<String, String> DECIMAL_FIELDS = new Map<String, String>{
        'prevDec' => 'Prev_Dec_Decimal__c',
        'jan' => 'Jan_Decimal__c',
        'feb' => 'Feb_Decimal__c',
        'mar' => 'Mar_Decimal__c',
        'apr' => 'Apr_Decimal__c',
        'may' => 'May_Decimal__c',
        'jun' => 'Jun_Decimal__c',
        'jul' => 'Jul_Decimal__c',
        'aug' => 'Aug_Decimal__c',
        'sep' => 'Sep_Decimal__c',
        'oct' => 'Oct_Decimal__c',
        'nov' => 'Nov_Decimal__c',
        'dec' => 'Dec_Decimal__c'
    };
    private static final Map<String, String> PERCENT_FIELDS = new Map<String, String>{
        'prevDec' => 'Prev_Dec_Percent__c',
        'jan' => 'Jan_Percent__c',
        'feb' => 'Feb_Percent__c',
        'mar' => 'Mar_Percent__c',
        'apr' => 'Apr_Percent__c',
        'may' => 'May_Percent__c',
        'jun' => 'Jun_Percent__c',
        'jul' => 'Jul_Percent__c',
        'aug' => 'Aug_Percent__c',
        'sep' => 'Sep_Percent__c',
        'oct' => 'Oct_Percent__c',
        'nov' => 'Nov_Percent__c',
        'dec' => 'Dec_Percent__c'
    };

    @AuraEnabled(cacheable=true)
    public static DynamicBudgetResponse getBudgetScreen(Id gwbYearId) {
        if (gwbYearId == null) {
            return new DynamicBudgetResponse();
        }

        GWB_Year__c headerRecord = [
            SELECT Id, Plant__c, Plant__r.Name, Plant__r.Auth_Region__c, Plant_Program__c,
                   Plant_Program__r.Name, Plant_Program__r.Product_Type__c, Plant_Sector__r.Part_Type__c,
                   Plant_Sector__r.Functional_Area__c, Sector__c, Status__c, Version__c,
                   M_Schedule_Version__c, Year__c, Target_Title__c
            FROM GWB_Year__c
            WHERE Id = :gwbYearId
            LIMIT 1
        ];

        DynamicBudgetResponse response = new DynamicBudgetResponse();
        response.header = new DynamicBudgetHeader(headerRecord);
        response.isPlantAdminLikeUser = isPlantAdminLikeUser();
        response.isPlantScopedUser = isPlantScopedTargetUser();
        validateTargetVisibility(headerRecord);
        response.vacationCoverageConfig = loadVacationCoverageConfig(
            headerRecord.Plant__c,
            headerRecord.Sector__c,
            headerRecord.Year__c
        );
        response.canEdit = isBaseEditAllowedByStatus(headerRecord);
        response.statusMessage = response.canEdit
            ? null
            : resolveReadOnlyStatusMessage(headerRecord);
        response.statusOptions = buildAllowedStatusOptions(headerRecord);
        response.canUpdateStatus = !response.statusOptions.isEmpty();
        response.comments = queryComments(gwbYearId);

        Set<String> sectorFilters = getSectorFilters(headerRecord.Sector__c);
        List<Target_UI_Controller__mdt> uiRows = [
            SELECT DeveloperName, MasterLabel, Sector__c, Section_Name__c, Section_Sequence__c, Category__c,
                   Source_Section__c, Parameter_Driver__c, Classification__c, Source_Type__c, UI_Line_Type__c,
                   UI_Sequence__c, Internal_Key__c, Source_Value__c, Value_Type__c, Is_Editable__c, Is_Active__c,
                   Fill_Forward_On_Edit__c,
                   Formula_Key__c, Formula_Tooltip__c, Avg_Total_Tooltip__c
            FROM Target_UI_Controller__mdt
            WHERE Is_Active__c = true
            AND Sector__c IN :sectorFilters
            ORDER BY Category__c ASC, UI_Sequence__c ASC, DeveloperName ASC
        ];
        if (uiRows.isEmpty()) {
            response.configurationMessage =
                'No active Target Screen Configuration metadata found for sector "' +
                String.valueOf(headerRecord.Sector__c) +
                '". Please deploy or activate Target_UI_Controller records for this sector.';
        }

        List<GWB_Month__c> parameterMonthRows = [
            SELECT Id, Section__c, Category__c, UI_Sequence__c, Value_Type__c, Parameter__c, Classification__c,
                   Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c,
                   Prev_Dec_Decimal__c, Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                   Prev_Dec_Percent__c, Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :gwbYearId
            AND Parameter__c != null
        ];
        Map<String, GWB_Month__c> parameterRowsByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c row : parameterMonthRows) {
            putSourceRowBySectionCandidates(
                parameterRowsByKey,
                'Parameter',
                row.Parameter__c,
                normalizeClassification(row.Classification__c),
                row.Section__c,
                row.Category__c,
                row
            );
        }

        List<GWB_Month__c> driverMonthRows = [
            SELECT Id, Section__c, Category__c, UI_Sequence__c, Value_Type__c, Driver__c, Classification__c,
                   Prev_Dec_Number__c,
                   Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :gwbYearId
            AND Driver__c != null
        ];
        Map<String, GWB_Month__c> driverRowsByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c row : driverMonthRows) {
            putSourceRowBySectionCandidates(
                driverRowsByKey,
                'Driver',
                normalizeDriver(row.Driver__c),
                normalizeClassification(row.Classification__c),
                row.Section__c,
                row.Category__c,
                row
            );
        }

        Map<String, Target_UI_Controller__mdt> parameterConfigsByStoredKey = buildStoredConfigLookup(uiRows, 'Parameter');
        Map<String, Target_UI_Controller__mdt> driverConfigsByStoredKey = buildStoredConfigLookup(uiRows, 'Driver');
        Map<String, DynamicBudgetSection> sectionsByName = new Map<String, DynamicBudgetSection>();
        List<String> sectionOrder = new List<String>();
        Set<String> seenUiRowKeys = new Set<String>();
        Set<String> matchedUiConfigNames = new Set<String>();

        for (GWB_Month__c storedRow : dedupeStoredRows(parameterMonthRows, 'Parameter')) {
            Target_UI_Controller__mdt matchedConfig = findStoredConfigMatch(
                parameterConfigsByStoredKey,
                storedRow,
                'Parameter'
            );
            DynamicBudgetRow row = buildDynamicRowFromStoredMonth(storedRow, 'Parameter', matchedConfig);
            addRowToSections(row, sectionsByName, sectionOrder);
            if (matchedConfig != null) {
                matchedUiConfigNames.add(matchedConfig.DeveloperName);
            }
        }

        for (GWB_Month__c storedRow : dedupeStoredRows(driverMonthRows, 'Driver')) {
            Target_UI_Controller__mdt matchedConfig = findStoredConfigMatch(
                driverConfigsByStoredKey,
                storedRow,
                'Driver'
            );
            DynamicBudgetRow row = buildDynamicRowFromStoredMonth(storedRow, 'Driver', matchedConfig);
            addRowToSections(row, sectionsByName, sectionOrder);
            if (matchedConfig != null) {
                matchedUiConfigNames.add(matchedConfig.DeveloperName);
            }
        }

        for (Target_UI_Controller__mdt config : uiRows) {
            String dedupeKey = buildUiRowDedupeKey(config);
            if (seenUiRowKeys.contains(dedupeKey)) {
                continue;
            }
            seenUiRowKeys.add(dedupeKey);
            if (matchedUiConfigNames.contains(config.DeveloperName)) {
                continue;
            }

            DynamicBudgetRow row = buildDynamicRow(config, parameterRowsByKey, driverRowsByKey);
            addRowToSections(row, sectionsByName, sectionOrder);
        }

        for (String sectionName : getOrderedSectionNames(sectionOrder)) {
            response.sections.add(sectionsByName.get(sectionName));
        }
        return response;
    }

    private static String mapSectionDisplayName(String sectionName, String categoryName) {
        String normalizedSection = String.isBlank(sectionName) ? '' : sectionName.trim().toLowerCase();
        if (normalizedSection.contains('non-driver') || normalizedSection.contains('op plan')) {
            return 'Op Plan';
        }
        if (normalizedSection.contains('driver') || normalizedSection.contains('headcount')) {
            return 'Headcount';
        }
        if (normalizedSection.contains('hour')) {
            return 'Hours';
        }

        String normalizedCategory = String.isBlank(categoryName) ? '' : categoryName.trim().toLowerCase();
        if (normalizedCategory.contains('op plan')) {
            return 'Op Plan';
        }
        if (normalizedCategory.contains('headcount')) {
            return 'Headcount';
        }
        if (normalizedCategory.contains('hour')) {
            return 'Hours';
        }
        return String.isBlank(categoryName) ? sectionName : categoryName;
    }

    private static Integer getCategoryDisplaySequence(String categoryName) {
        String normalizedCategory = String.isBlank(categoryName) ? '' : categoryName.trim().toLowerCase();
        if (normalizedCategory.contains('op plan')) {
            return 1;
        }
        if (normalizedCategory.contains('headcount')) {
            return 2;
        }
        if (normalizedCategory.contains('hour')) {
            return 3;
        }
        return 99;
    }

    private static List<String> getOrderedSectionNames(List<String> discoveredSectionNames) {
        List<String> orderedNames = new List<String>();
        Set<String> remainingNames = new Set<String>(discoveredSectionNames);
        for (String preferredName : new List<String>{ 'Op Plan', 'Headcount', 'Hours' }) {
            if (remainingNames.contains(preferredName)) {
                orderedNames.add(preferredName);
                remainingNames.remove(preferredName);
            }
        }

        List<String> additionalNames = new List<String>(remainingNames);
        additionalNames.sort();
        orderedNames.addAll(additionalNames);
        return orderedNames;
    }

    @AuraEnabled
    public static CommentDto saveBudgetComment(
        Id gwbYearId,
        Id commentId,
        String tableName,
        String rowKey,
        String rowLabel,
        String monthKey,
        String classification,
        String commentText,
        String valueSnapshot
    ) {
        try {
            if (gwbYearId == null || String.isBlank(commentText) || String.isBlank(rowKey) || String.isBlank(monthKey)) {
                throw new AuraHandledException('Select a budget cell and enter a comment before saving.');
            }

            GWB_Year__c header = [
                SELECT Id, Status__c, Sector__c
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];
            validateTargetAllowsComment(header);

            GWB_Budget_Comment__c commentRecord;
            if (commentId != null) {
                commentRecord = [
                    SELECT Id
                    FROM GWB_Budget_Comment__c
                    WHERE Id = :commentId
                    LIMIT 1
                ];
                commentRecord.Table_Name__c = tableName;
                commentRecord.Row_Key__c = rowKey;
                commentRecord.Row_Label__c = rowLabel;
                commentRecord.Month_Key__c = monthKey;
                commentRecord.Classification__c = classification;
                commentRecord.Comment_Text__c = commentText;
                commentRecord.Value_Snapshot__c = valueSnapshot;
                commentRecord.Cell_Key__c = buildCommentCellKey(tableName, rowKey, monthKey);
                update commentRecord;
            } else {
                commentRecord = new GWB_Budget_Comment__c(
                    GWB_Year__c = gwbYearId,
                    Table_Name__c = tableName,
                    Row_Key__c = rowKey,
                    Row_Label__c = rowLabel,
                    Month_Key__c = monthKey,
                    Classification__c = classification,
                    Comment_Text__c = commentText,
                    Value_Snapshot__c = valueSnapshot,
                    Cell_Key__c = buildCommentCellKey(tableName, rowKey, monthKey)
                );
                insert commentRecord;
                commentRecord = [
                    SELECT Id, CreatedDate
                    FROM GWB_Budget_Comment__c
                    WHERE Id = :commentRecord.Id
                    LIMIT 1
                ];
                commentRecord.Original_Created_Date__c = commentRecord.CreatedDate;
                update commentRecord;
            }

            commentRecord = [
                SELECT Id, Cell_Key__c, Table_Name__c, Row_Key__c, Row_Label__c, Month_Key__c,
                       Classification__c, Comment_Text__c, Value_Snapshot__c, CreatedDate,
                       Original_Created_Date__c, CreatedBy.Name
                FROM GWB_Budget_Comment__c
                WHERE Id = :commentRecord.Id
                LIMIT 1
            ];

            return new CommentDto(commentRecord);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(GENERIC_COMMENT_ERROR);
        }
    }

    @AuraEnabled
    public static SaveResponse saveBudgetRows(Id gwbYearId, List<RowInput> rows) {
        if (gwbYearId == null) {
            throw new AuraHandledException('saveBudgetRows failed: target record Id was not provided.');
        }
        if (rows == null || rows.isEmpty()) {
            throw new AuraHandledException('saveBudgetRows failed: no row payload was provided.');
        }

        GWB_Year__c header = [
            SELECT Id, Plant__c, Sector__c, Year__c, Version__c, M_Schedule_Version__c, Status__c
            FROM GWB_Year__c
            WHERE Id = :gwbYearId
            LIMIT 1
        ];
        validateTargetVisibility(header);
        validateTargetAllowsRowSave(header, rows);
        syncCalculatedRows(rows);

        Map<String, GWB_Month__c> existingParameterRowsByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c existingRow : [
            SELECT Id, Parameter__c, Classification__c, Section__c, Category__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :gwbYearId
            AND Parameter__c != null
        ]) {
            putSourceRowBySectionCandidates(
                existingParameterRowsByKey,
                'Parameter',
                existingRow.Parameter__c,
                normalizeClassification(existingRow.Classification__c),
                existingRow.Section__c,
                existingRow.Category__c,
                existingRow
            );
        }

        Map<String, GWB_Month__c> existingDriverRowsByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c existingRow : [
            SELECT Id, Driver__c, Classification__c, Section__c, Category__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :gwbYearId
            AND Driver__c != null
        ]) {
            putSourceRowBySectionCandidates(
                existingDriverRowsByKey,
                'Driver',
                normalizeDriver(existingRow.Driver__c),
                normalizeClassification(existingRow.Classification__c),
                existingRow.Section__c,
                existingRow.Category__c,
                existingRow
            );
        }

        List<SObject> upserts = new List<SObject>();
        Integer skippedBlankRows = 0;
        Integer skippedNonPersistableRows = 0;
        Integer skippedUnsupportedSourceRows = 0;
        List<String> skippedRowKeys = new List<String>();
        for (RowInput row : rows) {
            if (row == null || String.isBlank(row.key) || String.isBlank(row.sourceType)) {
                skippedBlankRows++;
                continue;
            }
            Boolean isEditableRow = row.editable == true;
            Boolean isPersistedTotalRow = isTotalLineType(row.lineType);
            Boolean isPersistedDerivedRow = isPersistableDerivedRow(row);
            Boolean isPersistedSourceRow = isPersistableSourceRow(row);
            if (!isEditableRow && !isPersistedTotalRow && !isPersistedDerivedRow && !isPersistedSourceRow && row.formulaKey != 'totalManpower') {
                skippedNonPersistableRows++;
                if (skippedRowKeys.size() < 5) {
                    skippedRowKeys.add(row.key);
                }
                continue;
            }
            if (row.sourceType == 'Parameter') {
                if (row.recordId == null) {
                    GWB_Month__c existingRow = findExistingParameterRow(existingParameterRowsByKey, row);
                    if (existingRow != null) {
                        row.recordId = existingRow.Id;
                    }
                }
                upserts.add(buildParameterRow(row, header));
            } else if (row.sourceType == 'Driver') {
                if (row.recordId == null) {
                    GWB_Month__c existingRow = existingDriverRowsByKey.get(
	                        buildSourceKey(
	                            'Driver',
	                            normalizeDriver(String.isBlank(row.sourceValue) ? row.label : row.sourceValue),
	                            row.classification,
	                            row.sourceSection
	                        )
	                    );
                    if (existingRow != null) {
                        row.recordId = existingRow.Id;
                    }
                }
                upserts.add(buildDriverRow(row, header));
            } else if (isPersistedDerivedRow) {
                if (!isSupportedParameterPicklistValue(resolveStoredParameterName(row))) {
                    skippedUnsupportedSourceRows++;
                    if (skippedRowKeys.size() < 5) {
                        skippedRowKeys.add(row.key);
                    }
                    continue;
                }
                if (row.recordId == null) {
                    GWB_Month__c existingRow = findExistingParameterRow(existingParameterRowsByKey, row);
                    if (existingRow != null) {
                        row.recordId = existingRow.Id;
                    }
                }
                upserts.add(buildParameterRow(row, header));
            } else {
                skippedUnsupportedSourceRows++;
                if (skippedRowKeys.size() < 5) {
                    skippedRowKeys.add(row.key);
                }
            }
        }
        List<SObject> dedupedUpserts = dedupeUpsertsById(upserts);
        if (dedupedUpserts.isEmpty()) {
            throw new AuraHandledException(
                'saveBudgetRows failed: no rows qualified for persistence. ' +
                'Submitted=' + rows.size() +
                ', skippedBlank=' + skippedBlankRows +
                ', skippedNonPersistable=' + skippedNonPersistableRows +
                ', skippedUnsupportedSource=' + skippedUnsupportedSourceRows +
                (skippedRowKeys.isEmpty() ? '' : ', sampleRowKeys=' + String.join(skippedRowKeys, ','))
            );
        }
        if (!dedupedUpserts.isEmpty()) {
            upsert dedupedUpserts;
        }

        SaveResponse response = new SaveResponse();
        response.savedRecordCount = dedupedUpserts.size();
        return response;
    }

    private static void syncCalculatedRows(List<RowInput> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Map<String, RowInput> rowsByKey = new Map<String, RowInput>();
        for (RowInput row : rows) {
            if (row == null || String.isBlank(row.key)) {
                continue;
            }
            rowsByKey.put(row.key.trim(), row);
        }

        syncCalculatedVolume(rowsByKey);
        syncVolumeVariance(rowsByKey);
        syncHeadcountRollups(rows);
    }

    private static void syncHeadcountRollups(List<RowInput> rows) {
        Map<String, RowInput> baseRowsByClassification = new Map<String, RowInput>();
        Map<String, RowInput> approvedRowsByClassification = new Map<String, RowInput>();
        Map<String, RowInput> totalRowsByClassification = new Map<String, RowInput>();
        Map<String, List<RowInput>> driverRowsByClassification = new Map<String, List<RowInput>>();

        for (RowInput row : rows) {
            if (row == null) {
                continue;
            }
            String classification = normalizeClassification(row.classification);
            if (classification == 'Total') {
                classification = 'Total';
            }

            if (isBaseHeadcountRow(row)) {
                baseRowsByClassification.put(classification, row);
            } else if (isApprovedTargetRow(row)) {
                approvedRowsByClassification.put(classification, row);
            } else if (isTotalManpowerRow(row)) {
                totalRowsByClassification.put(classification, row);
            } else if (isHeadcountDriverRow(row) && classification != 'Total') {
                if (!driverRowsByClassification.containsKey(classification)) {
                    driverRowsByClassification.put(classification, new List<RowInput>());
                }
                driverRowsByClassification.get(classification).add(row);
            }
        }

        for (String classification : new List<String>{ 'OTS', 'Skilled', 'Salaried' }) {
            RowInput baseRow = baseRowsByClassification.get(classification);
            RowInput approvedRow = approvedRowsByClassification.get(classification);
            List<RowInput> driverRows = driverRowsByClassification.get(classification);
            if (baseRow != null) {
                baseRow.values = buildBaseHeadcountRollupValues(baseRow, approvedRow, driverRows);
            }
            RowInput totalRow = totalRowsByClassification.get(classification);
            if (totalRow != null && baseRow != null) {
                totalRow.values = buildTotalManpowerRollupValues(baseRow, approvedRow, driverRows);
            }
        }

        syncTotalClassificationRow(baseRowsByClassification);
        syncTotalClassificationRow(totalRowsByClassification);
    }

    private static Map<String, Decimal> buildBaseHeadcountRollupValues(
        RowInput baseRow,
        RowInput approvedRow,
        List<RowInput> driverRows
    ) {
        Map<String, Decimal> nextValues = new Map<String, Decimal>{ 'prevDec' => safeDecimal(getMonthValue(baseRow, 'prevDec')) };
        Decimal runningTotal = safeDecimal(getMonthValue(baseRow, 'prevDec')) + safeDecimal(getMonthValue(approvedRow, 'prevDec'));
        for (String monthKey : MONTH_KEYS) {
            if (monthKey == 'prevDec') {
                continue;
            }
            runningTotal += sumMonthValues(driverRows, monthKey);
            nextValues.put(monthKey, runningTotal);
        }
        return nextValues;
    }

    private static Map<String, Decimal> buildTotalManpowerRollupValues(
        RowInput baseRow,
        RowInput approvedRow,
        List<RowInput> driverRows
    ) {
        Map<String, Decimal> nextValues = new Map<String, Decimal>();
        Decimal runningTotal = safeDecimal(getMonthValue(baseRow, 'prevDec')) + safeDecimal(getMonthValue(approvedRow, 'prevDec'));
        nextValues.put('prevDec', runningTotal);
        for (String monthKey : MONTH_KEYS) {
            if (monthKey == 'prevDec') {
                continue;
            }
            runningTotal += sumMonthValues(driverRows, monthKey);
            nextValues.put(monthKey, runningTotal);
        }
        return nextValues;
    }

    private static Decimal sumMonthValues(List<RowInput> rows, String monthKey) {
        Decimal total = 0;
        if (rows == null) {
            return total;
        }
        for (RowInput row : rows) {
            total += safeDecimal(getMonthValue(row, monthKey));
        }
        return total;
    }

    private static void syncTotalClassificationRow(Map<String, RowInput> rowsByClassification) {
        if (rowsByClassification == null || !rowsByClassification.containsKey('Total')) {
            return;
        }
        Boolean hasClassificationRows = false;
        for (String classification : new List<String>{ 'OTS', 'Skilled', 'Salaried' }) {
            if (rowsByClassification.containsKey(classification)) {
                hasClassificationRows = true;
                break;
            }
        }
        if (!hasClassificationRows) {
            return;
        }
        RowInput totalRow = rowsByClassification.get('Total');
        Map<String, Decimal> nextValues = new Map<String, Decimal>();
        for (String monthKey : MONTH_KEYS) {
            Decimal total = 0;
            for (String classification : new List<String>{ 'OTS', 'Skilled', 'Salaried' }) {
                total += safeDecimal(getMonthValue(rowsByClassification.get(classification), monthKey));
            }
            nextValues.put(monthKey, total);
        }
        totalRow.values = nextValues;
    }

    private static Boolean isTotalManpowerRow(RowInput row) {
        return row != null &&
            (
                row.formulaKey == 'totalManpower' ||
                resolveStoredParameterName(row) == TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER ||
                resolveStoredParameterName(row) == TOTAL_MANPOWER_PARAMETER
            );
    }

    private static Boolean isHeadcountDriverRow(RowInput row) {
        return row != null &&
            row.sourceType == 'Driver' &&
            resolveStoredCategory(row) == CATEGORY_HEADCOUNT;
    }

    private static void syncCalculatedVolume(Map<String, RowInput> rowsByKey) {
        RowInput calculatedVolumeRow = rowsByKey == null ? null : rowsByKey.get('calcVolume');
        if (calculatedVolumeRow == null) {
            return;
        }

        RowInput netJphRow = rowsByKey.get('netJph');
        RowInput paidHoursRow = rowsByKey.get('paidHoursPerCrew');
        RowInput productionDaysRow = rowsByKey.get('productionDays');
        RowInput eqSotDaysRow = rowsByKey.get('eqSotDays');
        RowInput shiftsRow = rowsByKey.get('shifts');
        if (netJphRow == null || paidHoursRow == null || productionDaysRow == null || eqSotDaysRow == null || shiftsRow == null) {
            return;
        }

        Map<String, Decimal> nextValues = new Map<String, Decimal>();
        for (String monthKey : MONTH_KEYS) {
            Decimal netJph = getMonthValue(netJphRow, monthKey);
            Decimal paidHours = getMonthValue(paidHoursRow, monthKey);
            Decimal productionDays = getMonthValue(productionDaysRow, monthKey);
            Decimal eqSotDays = getMonthValue(eqSotDaysRow, monthKey);
            Decimal shifts = getMonthValue(shiftsRow, monthKey);

            if (netJph == null && paidHours == null && productionDays == null && eqSotDays == null && shifts == null) {
                nextValues.put(monthKey, null);
                continue;
            }

            nextValues.put(
                monthKey,
                (
                    safeDecimal(netJph) *
                    safeDecimal(paidHours) *
                    (safeDecimal(productionDays) + safeDecimal(eqSotDays)) *
                    safeDecimal(shifts)
                ).setScale(0)
            );
        }
        calculatedVolumeRow.values = nextValues;
    }

    private static void syncVolumeVariance(Map<String, RowInput> rowsByKey) {
        RowInput varianceRow = rowsByKey == null ? null : rowsByKey.get('volumeVariance');
        if (varianceRow == null) {
            return;
        }

        RowInput scheduledVolumeRow = rowsByKey.get('scheduledVolume');
        RowInput calculatedVolumeRow = rowsByKey.get('calcVolume');
        if (scheduledVolumeRow == null || calculatedVolumeRow == null) {
            return;
        }
        Map<String, Decimal> nextValues = new Map<String, Decimal>();
        for (String monthKey : MONTH_KEYS) {
            Decimal scheduledVolume = getMonthValue(scheduledVolumeRow, monthKey);
            Decimal calculatedVolume = getMonthValue(calculatedVolumeRow, monthKey);
            nextValues.put(
                monthKey,
                scheduledVolume == null && calculatedVolume == null
                    ? null
                    : safeDecimal(scheduledVolume) - safeDecimal(calculatedVolume)
            );
        }
        varianceRow.values = nextValues;
    }

    private static Decimal getMonthValue(RowInput row, String monthKey) {
        return row == null || row.values == null || String.isBlank(monthKey) || !row.values.containsKey(monthKey)
            ? null
            : row.values.get(monthKey);
    }

    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    @AuraEnabled
    public static DynamicBudgetHeader updateTargetStatus(Id gwbYearId, String nextStatus) {
        if (gwbYearId == null) {
            throw new AuraHandledException('Select a valid target before updating status.');
        }
        if (String.isBlank(nextStatus)) {
            throw new AuraHandledException('Select a valid status before updating the target.');
        }

        GWB_Year__c header = [
            SELECT Id, Plant__c, Plant__r.Name, Plant__r.Auth_Region__c, Plant_Program__c,
                   Plant_Program__r.Name, Plant_Program__r.Product_Type__c, Plant_Sector__r.Part_Type__c,
                   Plant_Sector__r.Functional_Area__c, Sector__c, Status__c, Version__c,
                   M_Schedule_Version__c, Year__c, Target_Title__c
            FROM GWB_Year__c
            WHERE Id = :gwbYearId
            LIMIT 1
        ];
        validateTargetVisibility(header);
        validateTargetAllowsStatusUpdate(header, nextStatus);

        header.Status__c = nextStatus;
        update header;
        return new DynamicBudgetHeader(header);
    }

    private static DynamicBudgetRow buildDynamicRow(
        Target_UI_Controller__mdt config,
        Map<String, GWB_Month__c> parameterRowsByKey,
        Map<String, GWB_Month__c> driverRowsByKey
    ) {
        DynamicBudgetRow row = new DynamicBudgetRow();
        row.key = config.Internal_Key__c;
        row.category = config.Category__c;
        row.label = config.Parameter_Driver__c;
        row.sourceValue = String.isBlank(config.Source_Value__c) ? config.Parameter_Driver__c : config.Source_Value__c;
        row.classification = normalizeClassification(config.Classification__c);
        row.sourceType = config.Source_Type__c;
        row.sourceSection = resolveStoredSection(config);
        row.lineType = config.UI_Line_Type__c;
        row.sequence = Integer.valueOf(config.UI_Sequence__c);
        row.valueType = config.Value_Type__c;
        row.editable = config.Is_Editable__c;
        row.fillForwardOnEdit = config.Fill_Forward_On_Edit__c;
        row.formulaKey = config.Formula_Key__c;
        row.formulaTooltip = config.Formula_Tooltip__c;
        row.avgTotalTooltip = config.Avg_Total_Tooltip__c;
        row.values = new Map<String, Decimal>();

        GWB_Month__c sourceRow;
        if (config.Source_Type__c == 'Parameter') {
            sourceRow = findParameterSourceRow(parameterRowsByKey, row);
        } else if (config.Source_Type__c == 'Driver') {
            sourceRow = driverRowsByKey.get(
                buildSourceKey('Driver', normalizeDriver(row.sourceValue), row.classification, row.sourceSection)
            );
        }

        if (sourceRow != null) {
            row.recordId = sourceRow.Id;
            if (config.Source_Type__c == 'Parameter' && String.isNotBlank((String) sourceRow.get('Parameter__c'))) {
                row.label = (String) sourceRow.get('Parameter__c');
            } else if (config.Source_Type__c == 'Driver' && String.isNotBlank((String) sourceRow.get('Driver__c'))) {
                row.label = (String) sourceRow.get('Driver__c');
            }
        }

        for (String monthKey : MONTH_KEYS) {
            row.values.put(monthKey, extractValue(sourceRow, row.valueType, monthKey));
        }
        return row;
    }

    private static DynamicBudgetRow buildDynamicRowFromStoredMonth(
        GWB_Month__c storedRow,
        String sourceType,
        Target_UI_Controller__mdt matchedConfig
    ) {
        DynamicBudgetRow row = new DynamicBudgetRow();
        row.key = matchedConfig != null && String.isNotBlank(matchedConfig.Internal_Key__c)
            ? matchedConfig.Internal_Key__c
            : buildGeneratedStoredRowKey(storedRow, sourceType);
        row.category = matchedConfig != null && String.isNotBlank(matchedConfig.Category__c)
            ? matchedConfig.Category__c
            : String.isNotBlank(storedRow.Category__c)
                ? storedRow.Category__c
                : mapSectionDisplayName(storedRow.Section__c, storedRow.Category__c);
        row.label = matchedConfig != null && String.isNotBlank(matchedConfig.Parameter_Driver__c)
            ? matchedConfig.Parameter_Driver__c
            : sourceType == 'Driver' ? storedRow.Driver__c : storedRow.Parameter__c;
        row.sourceValue = matchedConfig != null
            ? String.isBlank(matchedConfig.Source_Value__c) ? matchedConfig.Parameter_Driver__c : matchedConfig.Source_Value__c
            : row.label;
        row.classification = String.isBlank(storedRow.Classification__c) && matchedConfig != null
            ? normalizeClassification(matchedConfig.Classification__c)
            : normalizeClassification(storedRow.Classification__c);
        row.sourceType = sourceType;
        row.sourceSection = matchedConfig != null
            ? resolveStoredSection(matchedConfig)
            : resolveStoredSectionFromCategory(row.category);
        row.lineType = matchedConfig != null && String.isNotBlank(matchedConfig.UI_Line_Type__c)
            ? matchedConfig.UI_Line_Type__c
            : (storedRow.Value_Type__c == VALUE_TYPE_TOTAL ? 'Total' : 'Input');
        row.sequence = matchedConfig != null && matchedConfig.UI_Sequence__c != null
            ? Integer.valueOf(matchedConfig.UI_Sequence__c)
            : storedRow.UI_Sequence__c != null
                ? Integer.valueOf(storedRow.UI_Sequence__c)
                : 999;
        row.valueType = resolveRenderedValueType(storedRow, matchedConfig, row.label, sourceType);
        row.editable = matchedConfig != null ? matchedConfig.Is_Editable__c : storedRow.Value_Type__c != VALUE_TYPE_TOTAL;
        row.fillForwardOnEdit = matchedConfig != null ? matchedConfig.Fill_Forward_On_Edit__c : false;
        row.formulaKey = matchedConfig != null ? matchedConfig.Formula_Key__c : null;
        row.formulaTooltip = matchedConfig != null ? matchedConfig.Formula_Tooltip__c : null;
        row.avgTotalTooltip = matchedConfig != null ? matchedConfig.Avg_Total_Tooltip__c : null;
        row.recordId = storedRow.Id;
        row.values = new Map<String, Decimal>();
        for (String monthKey : MONTH_KEYS) {
            row.values.put(monthKey, extractValue(storedRow, row.valueType, monthKey));
        }
        return row;
    }

    private static void addRowToSections(
        DynamicBudgetRow row,
        Map<String, DynamicBudgetSection> sectionsByName,
        List<String> sectionOrder
    ) {
        if (row == null) {
            return;
        }
        String sectionDisplayName = String.isBlank(row.category)
            ? mapSectionDisplayName(row.sourceSection, row.category)
            : row.category;
        if (!sectionsByName.containsKey(sectionDisplayName)) {
            DynamicBudgetSection section = new DynamicBudgetSection();
            section.name = sectionDisplayName;
            section.sequence = getCategoryDisplaySequence(sectionDisplayName);
            section.rows = new List<DynamicBudgetRow>();
            sectionsByName.put(sectionDisplayName, section);
            sectionOrder.add(sectionDisplayName);
        }
        sectionsByName.get(sectionDisplayName).rows.add(row);
    }

    private static Decimal extractValue(SObject row, String valueType, String monthKey) {
        if (row == null) {
            return null;
        }
        String normalizedValueType = normalizeValueType(valueType);
        String fieldName = normalizedValueType == 'decimal'
            ? DECIMAL_FIELDS.get(monthKey)
            : normalizedValueType == 'percent'
                ? PERCENT_FIELDS.get(monthKey)
                : NUMBER_FIELDS.get(monthKey);
        if (String.isBlank(fieldName)) {
            return null;
        }
        Object rawValue = row.get(fieldName);
        return rawValue == null ? null : (Decimal) rawValue;
    }

    private static SObject buildParameterRow(RowInput row, GWB_Year__c header) {
        GWB_Month__c record = row.recordId == null ? new GWB_Month__c() : new GWB_Month__c(Id = row.recordId);
        if (row.recordId == null) {
            record.GWB_Year__c = header.Id;
        }
        record.Plant__c = header.Plant__c;
        record.Sector__c = header.Sector__c;
        record.Year__c = header.Year__c;
        record.Data_Point_Value__c = String.isBlank(header.M_Schedule_Version__c) ? header.Version__c : header.M_Schedule_Version__c;
        record.Section__c = resolveStoredSection(row);
        record.Parameter__c = resolveStoredParameterName(row);
        record.Category__c = resolveStoredCategory(row);
        record.Classification__c = toStoredClassification(row.classification);
        record.UI_Sequence__c = row.sequence;
        record.Value_Type__c = resolveStoredValueType(row);
        clearValueFields(record);

        String normalizedValueType = normalizeValueType(row.valueType);
        Map<String, String> fieldMap = normalizedValueType == 'decimal'
            ? DECIMAL_FIELDS
            : normalizedValueType == 'percent'
                ? PERCENT_FIELDS
                : NUMBER_FIELDS;
        Boolean approvedTargetRow = isApprovedTargetRow(row);
        for (String monthKey : MONTH_KEYS) {
            if (approvedTargetRow && monthKey != 'prevDec') {
                continue;
            }
            if (row.values != null && row.values.containsKey(monthKey)) {
                record.put(fieldMap.get(monthKey), row.values.get(monthKey));
            }
        }
        Decimal annualSummaryValue = approvedTargetRow ? null : calculateAverageOrTotal(row);
        record.Avg_Total__c = annualSummaryValue;
        applyTypedAnnualTotal(record, row, annualSummaryValue);
        return record;
    }

    private static Boolean isApprovedTargetRow(RowInput row) {
        if (row == null) {
            return false;
        }
        String parameterValue = normalizeTargetParameterLabel(
            String.isBlank(row.sourceValue) ? row.label : row.sourceValue
        );
        return isApprovedTargetFamily(parameterValue);
    }

    private static SObject buildDriverRow(RowInput row, GWB_Year__c header) {
        GWB_Month__c record = row.recordId == null ? new GWB_Month__c() : new GWB_Month__c(Id = row.recordId);
        if (row.recordId == null) {
            record.GWB_Year__c = header.Id;
        }
        record.Driver__c = normalizeDriver(String.isBlank(row.sourceValue) ? row.label : row.sourceValue);
        record.Classification__c = toStoredClassification(row.classification);
        record.Plant__c = header.Plant__c;
        record.Sector__c = header.Sector__c;
        record.Year__c = header.Year__c;
        record.Data_Point_Value__c = String.isBlank(header.M_Schedule_Version__c) ? header.Version__c : header.M_Schedule_Version__c;
        record.Section__c = resolveStoredSection(row);
        record.Category__c = resolveStoredCategory(row);
        record.UI_Sequence__c = row.sequence;
        record.Value_Type__c = resolveStoredValueType(row);
        clearValueFields(record);
        for (String monthKey : MONTH_KEYS) {
            if (monthKey == 'prevDec') {
                continue;
            }
            if (row.values != null && row.values.containsKey(monthKey)) {
                record.put(NUMBER_FIELDS.get(monthKey), row.values.get(monthKey));
            }
        }
        Decimal annualSummaryValue = calculateAverageOrTotal(row);
        record.Avg_Total__c = annualSummaryValue;
        applyTypedAnnualTotal(record, row, annualSummaryValue);
        return record;
    }

    private static void applyTypedAnnualTotal(GWB_Month__c record, RowInput row, Decimal annualSummaryValue) {
        record.Annual_TotalDecimal1__c = null;
        record.Annual_TotalNumber1__c = null;
        record.Annual_TotalPercent1__c = null;

        if (annualSummaryValue == null || row == null || String.isBlank(row.valueType)) {
            return;
        }

        String valueType = row.valueType.trim().toLowerCase();
        if (valueType == 'decimal') {
            record.Annual_TotalDecimal1__c = annualSummaryValue;
        } else if (valueType == 'percent') {
            record.Annual_TotalPercent1__c = annualSummaryValue;
        } else {
            record.Annual_TotalNumber1__c = annualSummaryValue.setScale(0, RoundingMode.DOWN);
        }
    }

    private static Boolean isPersistableDerivedRow(RowInput row) {
        if (row == null || row.sourceType != 'Derived') {
            return false;
        }
        return isFormulaLineType(row.lineType) || isTotalLineType(row.lineType) || String.isNotBlank(row.formulaKey);
    }

    private static Boolean isPersistableSourceRow(RowInput row) {
        if (row == null || String.isBlank(row.sourceType)) {
            return false;
        }
        String valueType = String.isBlank(row.valueType) ? '' : row.valueType.trim().toLowerCase();
        if (valueType == 'text') {
            return false;
        }
        return row.sourceType == 'Parameter' || row.sourceType == 'Driver';
    }

    private static Boolean isFormulaLineType(String lineType) {
        return !String.isBlank(lineType) && lineType.trim().toLowerCase() == 'formula';
    }

    private static Boolean isTotalLineType(String lineType) {
        return !String.isBlank(lineType) && lineType.trim().toLowerCase() == 'total';
    }

    private static String normalizeValueType(String valueType) {
        String normalizedValueType = String.isBlank(valueType) ? '' : valueType.trim().toLowerCase();
        if (normalizedValueType == 'decimal' || normalizedValueType == 'percent') {
            return normalizedValueType;
        }
        return 'number';
    }

    private static Boolean isSupportedParameterPicklistValue(String parameterValue) {
        if (String.isBlank(parameterValue)) {
            return false;
        }
        for (Schema.PicklistEntry entry : GWB_Month__c.Parameter__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == parameterValue) {
                return true;
            }
        }
        return false;
    }

    private static List<SObject> dedupeUpsertsById(List<SObject> rows) {
        List<SObject> rowsWithoutIds = new List<SObject>();
        Map<Id, SObject> rowsById = new Map<Id, SObject>();
        if (rows == null) {
            return rowsWithoutIds;
        }

        for (SObject row : rows) {
            if (row == null) {
                continue;
            }
            Id rowId = (Id) row.get('Id');
            if (rowId == null) {
                rowsWithoutIds.add(row);
            } else {
                rowsById.put(rowId, row);
            }
        }

        rowsWithoutIds.addAll(rowsById.values());
        return rowsWithoutIds;
    }

    private static Decimal calculateAverageOrTotal(RowInput row) {
        if (row == null || row.values == null || row.values.isEmpty()) {
            return null;
        }

        if (isProductivityPercentSummaryRow(row)) {
            return calculateSingleAnnualPercent(row.values);
        }

        if (usesCumulativeAverageHeadcount(row)) {
            return calculateCumulativeAverage(row.values).setScale(2);
        }

        Decimal total = 0;
        Integer populatedMonthCount = 0;
        for (String monthKey : MONTH_KEYS) {
            if (monthKey == 'prevDec' || !row.values.containsKey(monthKey) || row.values.get(monthKey) == null) {
                continue;
            }
            total += row.values.get(monthKey);
            populatedMonthCount++;
        }
        if (populatedMonthCount == 0) {
            return null;
        }

        Decimal summaryValue = shouldAverageRowSummary(row)
            ? total / 12
            : total;
        return summaryValue.setScale(1);
    }

    private static Boolean isProductivityPercentSummaryRow(RowInput row) {
        if (row == null) {
            return false;
        }
        return row.key == 'summary-prod-pct' ||
            normalizeTargetParameterLabel(String.isBlank(row.sourceValue) ? row.label : row.sourceValue) == PRODUCTIVITY_PERCENT_PARAMETER ||
            row.formulaKey == 'prodPct';
    }

    private static Decimal calculateSingleAnnualPercent(Map<String, Decimal> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        if (values.containsKey('dec') && values.get('dec') != null) {
            return values.get('dec').setScale(1);
        }
        for (String monthKey : MONTH_KEYS) {
            if (monthKey != 'prevDec' && values.containsKey(monthKey) && values.get(monthKey) != null) {
                return values.get(monthKey).setScale(1);
            }
        }
        return null;
    }

    private static Decimal calculateCumulativeAverage(Map<String, Decimal> values) {
        Decimal runningTotal = 0;
        Decimal cumulativeSum = 0;
        for (String monthKey : MONTH_KEYS) {
            if (monthKey == 'prevDec') {
                continue;
            }
            runningTotal += values != null && values.containsKey(monthKey) && values.get(monthKey) != null
                ? values.get(monthKey)
                : 0;
            cumulativeSum += runningTotal;
        }
        return cumulativeSum / 12;
    }

    private static Boolean shouldAverageRowSummary(RowInput row) {
        if (row == null) {
            return false;
        }
        String valueType = normalizeValueType(row.valueType);
        if (valueType == 'percent') {
            return true;
        }

        String category = String.isBlank(row.category) ? '' : row.category.trim().toLowerCase();
        String rowKey = String.isBlank(row.key) ? '' : row.key.trim().toLowerCase();
        if (
            isBaseHeadcountRow(row) ||
            row.formulaKey == 'totalManpower' ||
            resolveStoredParameterName(row) == TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER
        ) {
            return true;
        }
        if (category == CATEGORY_HEADCOUNT.toLowerCase() && (rowKey.startsWith('base-') || rowKey.startsWith('total-'))) {
            return true;
        }
        if (category == CATEGORY_HOURS.toLowerCase() && row.formulaKey == 'combinedAbsence') {
            return true;
        }
        return false;
    }

    private static Boolean usesCumulativeAverageHeadcount(RowInput row) {
        if (row == null) {
            return false;
        }
        String storedParameterName = resolveStoredParameterName(row);
        if (
            isBaseHeadcountRow(row) ||
            isApprovedTargetRow(row) ||
            row.formulaKey == 'totalManpower' ||
            storedParameterName == TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER ||
            storedParameterName == TOTAL_MANPOWER_PARAMETER
        ) {
            return false;
        }
        String family = normalizeDriver(String.isBlank(row.sourceValue) ? row.label : row.sourceValue);
        family = String.isBlank(family) ? '' : family.trim().toLowerCase();
        return row.sourceType == 'Driver' && CUMULATIVE_AVERAGE_HC_FAMILIES.contains(family);
    }

    private static Boolean isBaseHeadcountRow(RowInput row) {
        String storedParameterName = resolveStoredParameterName(row);
        return storedParameterName == 'Base Headcount' ||
            storedParameterName == 'Base Headcount (non SUPP, no Apprentices)';
    }

    private static void clearValueFields(GWB_Month__c record) {
        for (String fieldName : NUMBER_FIELDS.values()) {
            if (fieldName != null) {
                record.put(fieldName, null);
            }
        }
        for (String fieldName : DECIMAL_FIELDS.values()) {
            if (fieldName != null) {
                record.put(fieldName, null);
            }
        }
        for (String fieldName : PERCENT_FIELDS.values()) {
            if (fieldName != null) {
                record.put(fieldName, null);
            }
        }
    }

    private static String buildSourceKey(String sourceType, String label, String classification, String sourceSection) {
        String normalizedSourceSection = normalizeStoredCategory(sourceSection);
        return String.join(
            new List<String>{
                String.isBlank(sourceType) ? '' : sourceType.trim(),
                String.isBlank(label) ? '' : label.trim(),
                String.isBlank(toStoredClassification(classification)) ? '' : toStoredClassification(classification),
                String.isBlank(normalizedSourceSection) ? '' : normalizedSourceSection
            },
            '|'
        );
    }

    private static void putSourceRowBySectionCandidates(
        Map<String, GWB_Month__c> rowsByKey,
        String sourceType,
        String label,
        String classification,
        String section,
        String category,
        GWB_Month__c row
    ) {
        if (rowsByKey == null || row == null) {
            return;
        }

        putSourceRowIfAbsent(rowsByKey, sourceType, label, classification, section, row);
        if (normalizeStoredCategory(section) != normalizeStoredCategory(category)) {
            putSourceRowIfAbsent(rowsByKey, sourceType, label, classification, category, row);
        }
    }

    private static void putSourceRowIfAbsent(
        Map<String, GWB_Month__c> rowsByKey,
        String sourceType,
        String label,
        String classification,
        String sourceSection,
        GWB_Month__c row
    ) {
        String key = buildSourceKey(sourceType, label, classification, sourceSection);
        if (!rowsByKey.containsKey(key)) {
            rowsByKey.put(key, row);
        }
    }

    private static Map<String, Target_UI_Controller__mdt> buildStoredConfigLookup(
        List<Target_UI_Controller__mdt> uiRows,
        String sourceType
    ) {
        Map<String, Target_UI_Controller__mdt> lookup = new Map<String, Target_UI_Controller__mdt>();
        for (Target_UI_Controller__mdt config : uiRows) {
            Boolean configMatchesSourceType = config != null && config.Source_Type__c == sourceType;
            Boolean derivedStoredAsParameter =
                config != null &&
                sourceType == 'Parameter' &&
                config.Source_Type__c == 'Derived';
            if (!configMatchesSourceType && !derivedStoredAsParameter) {
                continue;
            }
            for (String candidateLabel : buildStoredConfigCandidateLabels(config)) {
                String key = buildStoredMatchKey(
                    sourceType,
                    candidateLabel,
                    config.Classification__c,
                    config.Category__c
                );
                if (!lookup.containsKey(key)) {
                    lookup.put(key, config);
                }
                String categoryAgnosticKey = buildStoredMatchKey(
                    sourceType,
                    candidateLabel,
                    config.Classification__c,
                    null
                );
                if (!lookup.containsKey(categoryAgnosticKey)) {
                    lookup.put(categoryAgnosticKey, config);
                }
            }
        }
        return lookup;
    }

    private static Target_UI_Controller__mdt findStoredConfigMatch(
        Map<String, Target_UI_Controller__mdt> configsByStoredKey,
        GWB_Month__c storedRow,
        String sourceType
    ) {
        if (configsByStoredKey == null || storedRow == null) {
            return null;
        }

        Target_UI_Controller__mdt matchedConfig = configsByStoredKey.get(buildStoredRowMatchKey(storedRow, sourceType));
        if (matchedConfig != null) {
            return matchedConfig;
        }

        String label = sourceType == 'Driver' ? storedRow.Driver__c : storedRow.Parameter__c;
        return configsByStoredKey.get(
            buildStoredMatchKey(sourceType, label, storedRow.Classification__c, null)
        );
    }

    private static List<String> buildStoredConfigCandidateLabels(Target_UI_Controller__mdt config) {
        List<String> labels = new List<String>();
        if (config == null) {
            return labels;
        }
        addStoredConfigCandidateLabel(labels, config.Parameter_Driver__c);
        addStoredConfigCandidateLabel(labels, config.Source_Value__c);
        if (containsApprovedTargetFamily(labels)) {
            addApprovedTargetCandidateLabels(labels);
        }
        if (config.Formula_Key__c == 'totalManpower') {
            if (!labels.contains(TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER)) {
                labels.add(TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER);
            }
            if (!labels.contains(TOTAL_MANPOWER_PARAMETER)) {
                labels.add(TOTAL_MANPOWER_PARAMETER);
            }
        }
        return labels;
    }

    private static void addStoredConfigCandidateLabel(List<String> labels, String label) {
        if (String.isBlank(label)) {
            return;
        }
        addUniqueLabel(labels, label);
        String normalizedLabel = normalizeTargetParameterLabel(label);
        addUniqueLabel(labels, normalizedLabel);

        if (normalizedLabel == COMBINED_ABSENCE_PARAMETER) {
            addUniqueLabel(labels, 'Absenteeism % + Summer VRO%');
        } else if (normalizedLabel == ST_HOURS_INCLUDE_ADDITIONAL_ST_PARAMETER) {
            addUniqueLabel(labels, 'ST Hours (inc. Add\'l ST Hours below)');
        } else if (normalizedLabel == NSOT_HOURS_PARAMETER) {
            addUniqueLabel(labels, 'NSOT Hours (NSOT % = NSOT / (ST + SOT)');
        } else if (normalizedLabel == ADDITIONAL_ST_HOURS_PARAMETER) {
            addUniqueLabel(labels, 'Additional Straight Time Hours (downweeks, etc)');
        } else if (normalizedLabel == 'Calculated Volume incl. SOT') {
            addUniqueLabel(labels, 'Calculated Volume including SOT days');
            addUniqueLabel(labels, 'Calculated Volume incl. SOT days');
        } else if (normalizedLabel == 'Volume Variance') {
            addUniqueLabel(labels, 'Scheduled Volume minus Calculated Volume');
        } else if (isApprovedTargetFamily(normalizedLabel)) {
            addApprovedTargetCandidateLabels(labels);
        }
    }

    private static Boolean containsApprovedTargetFamily(List<String> labels) {
        if (labels == null) {
            return false;
        }
        for (String label : labels) {
            if (isApprovedTargetFamily(label)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isApprovedTargetFamily(String parameterValue) {
        String normalized = String.isBlank(parameterValue) ? '' : parameterValue.trim().toLowerCase();
        return normalized.contains('approved target') || normalized.contains('advanced target changes');
    }

    private static void addApprovedTargetCandidateLabels(List<String> labels) {
        addUniqueLabel(labels, PREVIOUS_YE_APPROVED_TARGET_CHANGES_PARAMETER);
        addUniqueLabel(labels, LEGACY_APPROVED_TARGET_PARAMETER);
        addUniqueLabel(labels, LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER);
    }

    private static void addUniqueLabel(List<String> labels, String label) {
        if (String.isNotBlank(label) && !labels.contains(label)) {
            labels.add(label);
        }
    }

    private static List<GWB_Month__c> dedupeStoredRows(List<GWB_Month__c> storedRows, String sourceType) {
        Map<String, GWB_Month__c> rowsByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c row : storedRows) {
            String key = buildStoredRowMatchKey(row, sourceType);
            if (!rowsByKey.containsKey(key)) {
                rowsByKey.put(key, row);
            }
        }
        return rowsByKey.values();
    }

    private static String buildStoredRowMatchKey(GWB_Month__c row, String sourceType) {
        String label = sourceType == 'Driver' ? row.Driver__c : row.Parameter__c;
        return buildStoredMatchKey(sourceType, label, row.Classification__c, row.Category__c);
    }

    private static String buildStoredMatchKey(
        String sourceType,
        String label,
        String classification,
        String category
    ) {
        return String.join(
            new List<String>{
                String.isBlank(sourceType) ? '' : sourceType.trim().toLowerCase(),
                String.isBlank(label) ? '' : label.trim().toLowerCase(),
                String.isBlank(toStoredClassification(classification)) ? '' : toStoredClassification(classification).toLowerCase(),
                String.isBlank(category) ? '' : category.trim().toLowerCase()
            },
            '|'
        );
    }

    private static String buildGeneratedStoredRowKey(GWB_Month__c row, String sourceType) {
        String label = sourceType == 'Driver' ? row.Driver__c : row.Parameter__c;
        return String.join(
            new List<String>{
                sourceType.toLowerCase(),
                String.isBlank(label) ? 'row' : label.trim().toLowerCase().replace(' ', '-'),
                normalizeClassification(row.Classification__c).toLowerCase()
            },
            '-'
        );
    }

    private static GWB_Month__c findExistingParameterRow(Map<String, GWB_Month__c> existingParameterRowsByKey, RowInput row) {
        if (existingParameterRowsByKey == null || row == null) {
            return null;
        }

        GWB_Month__c existingRow;
        for (String candidateParameterName : getStoredParameterCandidates(row)) {
            existingRow = existingParameterRowsByKey.get(
                buildSourceKey('Parameter', candidateParameterName, row.classification, row.sourceSection)
            );
            if (existingRow != null) {
                break;
            }
        }
        if (existingRow == null && row.formulaKey == 'totalManpower') {
            existingRow = existingParameterRowsByKey.get(
                buildSourceKey(
                    'Parameter',
                    TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER,
                    row.classification,
                    row.sourceSection
                )
            );
        }
        return existingRow;
    }

    private static GWB_Month__c findParameterSourceRow(
        Map<String, GWB_Month__c> parameterRowsByKey,
        DynamicBudgetRow row
    ) {
        if (parameterRowsByKey == null || row == null) {
            return null;
        }

        GWB_Month__c sourceRow;
        for (String candidateParameterName : getStoredParameterCandidates(row)) {
            sourceRow = parameterRowsByKey.get(
                buildSourceKey('Parameter', candidateParameterName, row.classification, row.sourceSection)
            );
            if (sourceRow != null) {
                break;
            }
        }
        if (sourceRow == null && row.formulaKey == 'totalManpower') {
            sourceRow = parameterRowsByKey.get(
                buildSourceKey(
                    'Parameter',
                    TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER,
                    row.classification,
                    row.sourceSection
                )
            );
        }
        return sourceRow;
    }

    private static String resolveStoredParameterName(RowInput row) {
        if (row != null && row.formulaKey == 'totalManpower') {
            return TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER;
        }
        String parameterValue = String.isBlank(row.sourceValue) ? row.label : row.sourceValue;
        parameterValue = normalizeTargetParameterLabel(parameterValue);
        if (isApprovedTargetFamily(parameterValue)) {
            return PREVIOUS_YE_APPROVED_TARGET_CHANGES_PARAMETER;
        }
        return parameterValue;
    }

    private static List<String> getStoredParameterCandidates(RowInput row) {
        List<String> candidates = new List<String>();
        if (row == null) {
            return candidates;
        }

        String persistedParameterValue = resolveStoredParameterName(row);
        if (String.isNotBlank(persistedParameterValue)) {
            candidates.add(persistedParameterValue);
        }
        addStoredConfigCandidateLabel(candidates, persistedParameterValue);

        String rawParameterValue = String.isBlank(row.sourceValue) ? row.label : row.sourceValue;
        rawParameterValue = normalizeTargetParameterLabel(rawParameterValue);
        if (String.isNotBlank(rawParameterValue) && !candidates.contains(rawParameterValue)) {
            candidates.add(rawParameterValue);
        }
        addStoredConfigCandidateLabel(candidates, rawParameterValue);
        if (isApprovedTargetFamily(rawParameterValue)) {
            addApprovedTargetCandidateLabels(candidates);
        }
        return candidates;
    }

    private static List<String> getStoredParameterCandidates(DynamicBudgetRow row) {
        List<String> candidates = new List<String>();
        if (row == null) {
            return candidates;
        }

        String primaryValue = row.sourceValue;
        primaryValue = normalizeTargetParameterLabel(primaryValue);
        if (String.isNotBlank(primaryValue)) {
            candidates.add(primaryValue);
        }
        addStoredConfigCandidateLabel(candidates, primaryValue);
        if (isApprovedTargetFamily(primaryValue)) {
            addApprovedTargetCandidateLabels(candidates);
        }
        return candidates;
    }

    private static String normalizeTargetParameterLabel(String parameterValue) {
        if (String.isBlank(parameterValue)) {
            return parameterValue;
        }
        String normalized = parameterValue.trim();
        if (normalized == 'Absenteeism % + Summer VRO%') {
            return COMBINED_ABSENCE_PARAMETER;
        }
        if (normalized == 'ST Hours (inc. Add\'l ST Hours below)') {
            return ST_HOURS_INCLUDE_ADDITIONAL_ST_PARAMETER;
        }
        if (normalized == 'NSOT Hours (NSOT % = NSOT / (ST + SOT)') {
            return NSOT_HOURS_PARAMETER;
        }
        if (normalized == 'Additional Straight Time Hours (downweeks, etc)') {
            return ADDITIONAL_ST_HOURS_PARAMETER;
        }
        if (normalized == 'Calculated Volume including SOT days' ||
            normalized == 'Calculated Volume incl. SOT days') {
            return 'Calculated Volume incl. SOT';
        }
        if (normalized == PREVIOUS_YE_APPROVED_TARGET_CHANGES_PARAMETER ||
            normalized == LEGACY_APPROVED_TARGET_PARAMETER ||
            normalized == LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER) {
            return PREVIOUS_YE_APPROVED_TARGET_CHANGES_PARAMETER;
        }
        return normalized;
    }

    private static String resolveStoredCategory(RowInput row) {
        if (row == null) {
            return null;
        }
        String explicitCategory = normalizeStoredCategory(row.category);
        if (String.isNotBlank(explicitCategory)) {
            return explicitCategory;
        }

        String sectionCategory = normalizeStoredCategory(row.sourceSection);
        if (String.isNotBlank(sectionCategory)) {
            return sectionCategory;
        }

        String combined = String.join(
            new List<String>{
                String.valueOf(row.category),
                String.valueOf(row.label),
                String.valueOf(row.sourceValue),
                String.valueOf(row.formulaKey)
            },
            ' '
        ).toLowerCase();
        if (combined.contains('hour')) {
            return CATEGORY_HOURS;
        }
        if (row.formulaKey == 'totalManpower' ||
            combined.contains('headcount') ||
            combined.contains('target changes') ||
            combined.contains('absenteeism') ||
            combined.contains('nsot')) {
            return CATEGORY_HEADCOUNT;
        }
        if (combined.contains('crew') ||
            combined.contains('shift') ||
            combined.contains('jph') ||
            combined.contains('volume') ||
            combined.contains('working day') ||
            combined.contains('sot days')) {
            return CATEGORY_OP_PLAN;
        }
        return CATEGORY_HOURS;
    }

    private static String normalizeStoredCategory(String rawCategory) {
        if (String.isBlank(rawCategory)) {
            return null;
        }

        String normalizedCategory = rawCategory.trim().toLowerCase();
        if (normalizedCategory == CATEGORY_OP_PLAN.toLowerCase() ||
            normalizedCategory == SECTION_SCHEDULED_VOLUME.toLowerCase() ||
            normalizedCategory == LEGACY_SECTION_SCHEDULED_VOLUME.toLowerCase() ||
            normalizedCategory.contains('scheduled') ||
            normalizedCategory.contains('non-driver')) {
            return CATEGORY_OP_PLAN;
        }
        if (normalizedCategory == CATEGORY_HEADCOUNT.toLowerCase() ||
            normalizedCategory == SECTION_MANPOWER.toLowerCase() ||
            normalizedCategory == LEGACY_SECTION_MANPOWER.toLowerCase() ||
            normalizedCategory.contains('headcount') ||
            normalizedCategory.contains('manpower')) {
            return CATEGORY_HEADCOUNT;
        }
        if (normalizedCategory == CATEGORY_HOURS.toLowerCase() ||
            normalizedCategory == SECTION_HOURS.toLowerCase() ||
            normalizedCategory.contains('hour')) {
            return CATEGORY_HOURS;
        }
        return null;
    }

    private static String resolveStoredSectionFromCategory(String category) {
        String normalizedCategory = String.isBlank(category) ? '' : category.trim().toLowerCase();
        if (normalizedCategory == CATEGORY_HEADCOUNT.toLowerCase()) {
            return SECTION_MANPOWER;
        }
        if (normalizedCategory == CATEGORY_OP_PLAN.toLowerCase()) {
            return SECTION_SCHEDULED_VOLUME;
        }
        if (normalizedCategory == LEGACY_SECTION_MANPOWER.toLowerCase()) {
            return SECTION_MANPOWER;
        }
        if (normalizedCategory == LEGACY_SECTION_SCHEDULED_VOLUME.toLowerCase()) {
            return SECTION_SCHEDULED_VOLUME;
        }
        return SECTION_HOURS;
    }

    private static String resolveSectionForParameter(String label) {
        if (label == 'Base Headcount' ||
            isApprovedTargetFamily(label) ||
            label == 'Absenteeism %' ||
            label == 'NSOT %' ||
            label == 'Additional Straight Time Hours Adjustment' ||
            label == TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER ||
            label == TOTAL_MANPOWER_PARAMETER) {
            return SECTION_MANPOWER;
        }
        if (label == 'Additional Straight Time Hours' ||
            label == 'Additional OT Time Hours (Manual)' ||
            label == 'Absenteeism % + Summer VRO %' ||
            label == 'Scheduled Overtime Hours' ||
            label == 'ST Hours (inc. Add\'l ST Hours)' ||
            label == 'NSOT Hours' ||
            label == 'Total Hours' ||
            label == 'AHPU Monthly' ||
            label == 'AHPU YTD' ||
            label == 'WHPU Monthly') {
            return SECTION_HOURS;
        }
        return SECTION_SCHEDULED_VOLUME;
    }

    private static String resolveStoredSection(RowInput row) {
        if (row == null) {
            return null;
        }
        if (row.sourceType == 'Parameter') {
            return resolveSectionForParameter(resolveStoredParameterName(row));
        }
        return resolveStoredSectionFromCategory(resolveStoredCategory(row));
    }

    private static String resolveStoredSection(Target_UI_Controller__mdt config) {
        if (config == null) {
            return null;
        }
        if (config.Source_Type__c == 'Parameter') {
            String parameterValue = String.isBlank(config.Source_Value__c) ? config.Parameter_Driver__c : config.Source_Value__c;
            if (config.Formula_Key__c == 'totalManpower') {
                parameterValue = TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER;
            }
            return resolveSectionForParameter(parameterValue);
        }
        String storedCategory = String.isNotBlank(config.Category__c)
            ? config.Category__c
            : mapSectionDisplayName(config.Section_Name__c, config.Category__c);
        return resolveStoredSectionFromCategory(storedCategory);
    }

    private static String resolveRenderedValueType(
        GWB_Month__c storedRow,
        Target_UI_Controller__mdt matchedConfig,
        String label,
        String sourceType
    ) {
        if (sourceType == 'Driver') {
            return 'number';
        }
        String configuredValueType = matchedConfig == null ? null : matchedConfig.Value_Type__c;
        return normalizeConfiguredValueType(configuredValueType, label);
    }

    private static String normalizeConfiguredValueType(String configuredValueType, String label) {
        String normalized = String.isBlank(configuredValueType) ? null : configuredValueType.trim().toLowerCase();
        if (normalized == 'number' || normalized == 'decimal' || normalized == 'percent' || normalized == 'percentage') {
            return normalized == 'percentage' ? 'percent' : normalized;
        }
        return resolveValueType(label);
    }

    private static String resolveValueType(String label) {
        if (label == 'Net/Net JPH' ||
            label == 'Paid Hours Per CREW' ||
            label == 'Available Working Days/Month' ||
            label == 'Production Working Days/Month' ||
            label == 'HARBOUR STROKES HPU' ||
            label == 'SOT from line time' ||
            label == 'Final Assembly Line JPH' ||
            label == 'SOT days (Weekends)' ||
            label == 'EQ SOT Days') {
            return 'decimal';
        }
        if (label == 'Absenteeism %' ||
            label == 'Equivalent SOT %' ||
            label == 'SOT percent from weekend days' ||
            label == 'NSOT %' ||
            label == PRODUCTIVITY_PERCENT_PARAMETER) {
            return 'percent';
        }
        return 'number';
    }

    private static String resolveStoredValueType(RowInput row) {
        if (row == null) {
            return VALUE_TYPE_VALUE;
        }
        if (row.formulaKey == 'totalManpower') {
            return isTotalClassification(row.classification) ? VALUE_TYPE_TOTAL : VALUE_TYPE_VALUE;
        }
        if (isTotalLineType(row.lineType)) {
            return VALUE_TYPE_TOTAL;
        }
        return VALUE_TYPE_VALUE;
    }

    private static Boolean isTotalClassification(String classification) {
        return String.isBlank(classification) || normalizeClassification(classification) == 'Total';
    }

    private static String normalizeClassification(String classification) {
        if (String.isBlank(classification)) {
            return '';
        }
        String normalized = classification.trim();
        String lower = normalized.toLowerCase();
        if (lower == 'shared' || lower == 'mschedule' || lower == 'calculated') {
            return '';
        }
        if (lower == 'ost' || lower == 'ots') {
            return 'OTS';
        }
        if (lower == 'sk') {
            return 'Skilled';
        }
        if (lower == 'sal') {
            return 'Salaried';
        }
        if (lower == 'salary' || lower == 'salaried') {
            return 'Salaried';
        }
        if (lower == 'skilled') {
            return 'Skilled';
        }
        if (lower == 'total') {
            return 'Total';
        }
        return normalized;
    }

    private static String toStoredClassification(String classification) {
        String normalized = normalizeClassification(classification);
        if (normalized == 'Total' && !supportsTotalClassificationValue()) {
            return null;
        }
        return String.isBlank(normalized) ? null : normalized;
    }

    private static Boolean supportsTotalClassificationValue() {
        for (Schema.PicklistEntry entry : GWB_Month__c.Classification__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == 'Total') {
                return true;
            }
        }
        return false;
    }

    private static String normalizeDriver(String driver) {
        if (driver == 'MBC' || driver == 'ARC') {
            return 'ARC';
        }
        if (driver == 'Op Plan Changes' || driver == 'Op Plan') {
            return 'Op Plan';
        }
        if (driver == 'Vacation Coverage' || driver == 'Vacation Replacement') {
            return 'Vacation Replacement';
        }
        if (driver == 'Content Changes' || driver == 'Content') {
            return 'Content';
        }
        if (driver == 'Other / Excess' || driver == 'Other/Excess') {
            return 'Other/Excess';
        }
        if (driver == 'Additional Straight Time Hours Adjustment') {
            return 'Additional ST Adjust';
        }
        return driver;
    }

    private static Boolean isPublishedStatus(String statusValue) {
        return normalizeStatus(statusValue) == PUBLISHED_STATUS.toLowerCase();
    }

    private static Boolean isLockedStatus(String statusValue) {
        return normalizeStatus(statusValue) == LOCKED_STATUS.toLowerCase();
    }

    private static Boolean isPlantReviewCompleteStatus(String statusValue) {
        return normalizeStatus(statusValue) == PLANT_REVIEW_COMPLETE_STATUS.toLowerCase();
    }

    private static Boolean isPlantReviewStatus(String statusValue) {
        return normalizeStatus(statusValue) == PLANT_REVIEW_STATUS.toLowerCase();
    }

    private static String normalizeStatus(String statusValue) {
        return String.valueOf(statusValue).trim().toLowerCase();
    }

    private static Boolean hasPlantAdminPermission() {
        if (Test.isRunningTest() && plantAdminPermissionOverride != null) {
            return plantAdminPermissionOverride;
        }
        return FeatureManagement.checkPermission(PLANT_ADMIN_PERMISSION);
    }

    private static Boolean hasIndustrialEngineerPermission() {
        return FeatureManagement.checkPermission(INDUSTRIAL_ENGINEER_PERMISSION);
    }

    private static Boolean hasPlantViewerPermission() {
        return FeatureManagement.checkPermission(PLANT_VIEWER_PERMISSION);
    }

    private static Boolean isGpsSector(String sectorValue) {
        return String.valueOf(sectorValue).trim().toLowerCase().contains('gps');
    }

    private static Boolean isBaseEditAllowedByStatus(GWB_Year__c header) {
        if (header == null) {
            return false;
        }
        validateTargetVisibility(header);
        if (isIndustrialEngineerUser() || isPlantViewerUser()) {
            return false;
        }
        if (isPublishedStatus(header.Status__c) || isLockedStatus(header.Status__c)) {
            return false;
        }
        if (isPlantAdminLikeUser() && isPlantReviewCompleteStatus(header.Status__c)) {
            return false;
        }
        return true;
    }

    private static String resolveReadOnlyStatusMessage(GWB_Year__c header) {
        if (header == null) {
            return 'Target rows are read-only right now.';
        }
        if (isPublishedStatus(header.Status__c)) {
            return 'Target rows are read-only when the target status is Published.';
        }
        if (isLockedStatus(header.Status__c)) {
            return 'Target rows are read-only when the target status is Locked.';
        }
        if (isIndustrialEngineerUser() || isPlantViewerUser()) {
            return 'Target rows are read-only for your access level.';
        }
        if (isPlantAdminLikeUser() && isPlantReviewCompleteStatus(header.Status__c)) {
            return 'Target rows are read-only when the target status is Plant Review Complete.';
        }
        return 'Target rows are read-only for the current status.';
    }

    private static void validateTargetAllowsComment(GWB_Year__c header) {
        validateTargetVisibility(header);
        if (!isBaseEditAllowedByStatus(header)) {
            throw new AuraHandledException(
                'Comments cannot be saved when the target is read-only for the current status.'
            );
        }
    }

    private static void validateTargetAllowsRowSave(GWB_Year__c header, List<RowInput> rows) {
        validateTargetVisibility(header);
        if (!isBaseEditAllowedByStatus(header)) {
            throw new AuraHandledException(resolveReadOnlyStatusMessage(header));
        }
        if (isPlantAdminLikeUser() && isPlantReviewStatus(header.Status__c) && !isGpsSector(header.Sector__c)) {
            for (RowInput row : rows) {
                if (row == null || String.isBlank(row.key)) {
                    continue;
                }
                if (!ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.contains(row.key)) {
                    throw new AuraHandledException(
                        'Only Additional Straight Time adjustment rows can be saved in Plant Review for Plant Admin users.'
                    );
                }
            }
        }
    }

    private static void validateTargetAllowsStatusUpdate(GWB_Year__c header, String nextStatus) {
        List<PicklistOption> allowedOptions = buildAllowedStatusOptions(header);
        Set<String> allowedValues = new Set<String>();
        for (PicklistOption option : allowedOptions) {
            allowedValues.add(option.value);
        }
        if (!allowedValues.contains(nextStatus)) {
            throw new AuraHandledException('You do not have access to update the target to the selected status.');
        }
    }

    private static void validateTargetVisibility(GWB_Year__c header) {
        if (header == null || !isPlantScopedTargetUser()) {
            return;
        }
        if (!new Set<String>{
            DRAFT_STATUS,
            PLANT_REVIEW_STATUS,
            PLANT_REVIEW_COMPLETE_STATUS,
            PUBLISHED_STATUS,
            LOCKED_STATUS
        }.contains(header.Status__c)) {
            throw new AuraHandledException('This target status is not available for your access level.');
        }
    }

    private static List<PicklistOption> buildAllowedStatusOptions(GWB_Year__c header) {
        List<PicklistOption> options = new List<PicklistOption>();
        if (header == null) {
            return options;
        }
        if (isIndustrialEngineerUser() || isPlantViewerUser()) {
            return options;
        }
        if (isPlantAdminLikeUser()) {
            if (isPlantReviewStatus(header.Status__c)) {
                options.add(new PicklistOption(PLANT_REVIEW_COMPLETE_STATUS, PLANT_REVIEW_COMPLETE_STATUS));
            }
            return options;
        }

        for (Schema.PicklistEntry entry : GWB_Year__c.Status__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String value = entry.getValue();
            if (value == PUBLISHED_STATUS || value == LOCKED_STATUS) {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), value));
        }
        return options;
    }

    private static Boolean isPlantAdminLikeUser() {
        if (hasPlantAdminPermission()) {
            return true;
        }
        String persona = getCurrentUserPersona();
        return persona.contains('plantadmin') || (persona.contains('backup') && persona.contains('plant'));
    }

    private static Boolean isIndustrialEngineerUser() {
        if (hasIndustrialEngineerPermission()) {
            return true;
        }
        return getCurrentUserPersona().contains('industrial_engineer');
    }

    private static Boolean isPlantViewerUser() {
        if (hasPlantViewerPermission()) {
            return true;
        }
        return getCurrentUserPersona().contains('plant_viewer');
    }

    private static Boolean isPlantScopedTargetUser() {
        return isPlantAdminLikeUser() || isIndustrialEngineerUser() || isPlantViewerUser();
    }

    private static String getCurrentUserPersona() {
        if (Test.isRunningTest() && currentUserPersonaOverride != null) {
            return currentUserPersonaOverride.toLowerCase();
        }
        List<User> users = [
            SELECT Persona__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return users.isEmpty() || String.isBlank(users[0].Persona__c)
            ? ''
            : users[0].Persona__c.toLowerCase();
    }

    private static String buildUiRowDedupeKey(Target_UI_Controller__mdt config) {
        return String.join(new List<String>{
            String.isBlank(config.Category__c) ? '' : config.Category__c.trim().toLowerCase(),
            String.isBlank(config.Internal_Key__c) ? '' : config.Internal_Key__c.trim().toLowerCase(),
            normalizeClassification(config.Classification__c),
            String.isBlank(config.Source_Type__c) ? '' : config.Source_Type__c.trim().toLowerCase(),
            String.isBlank(config.Source_Value__c) ? '' : config.Source_Value__c.trim().toLowerCase(),
            String.isBlank(config.Parameter_Driver__c) ? '' : config.Parameter_Driver__c.trim().toLowerCase()
        }, '|');
    }

    private static Set<String> getSectorFilters(String sectorValue) {
        Set<String> filters = new Set<String>();
        String raw = String.valueOf(sectorValue).trim();
        if (!String.isBlank(raw)) {
            filters.add(raw);
            filters.add(raw.toLowerCase());
            filters.add(raw.toUpperCase());
            filters.add(raw.substring(0, 1).toUpperCase() + raw.substring(1).toLowerCase());
        }

        String normalized = raw.toLowerCase();
        if (normalized.contains('gps')) {
            filters.add('GPS');
            filters.add('Gps');
        } else if (normalized.contains('stamp') || normalized.contains('press')) {
            filters.add('Stamping');
            filters.add('Press');
        } else if (normalized.contains('poly')) {
            filters.add('Polymers');
        } else {
            filters.add('Assembly');
        }
        return filters;
    }

    private static VacationCoverageConfigDto loadVacationCoverageConfig(Id plantId, String sector, String year) {
        if (plantId == null || String.isBlank(year) || String.valueOf(sector).trim() != 'Assembly') {
            return null;
        }

        List<GWB_Vacation_Coverage__c> records = [
            SELECT Id, Vacation_Percent__c, Entry_Month_Year__c, Exit_Month_Year__c
            FROM GWB_Vacation_Coverage__c
            WHERE Plant__c = :plantId
            AND Year__c = :year
            AND Sector__c = :sector
            AND Classification__c = 'OTS'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (records.isEmpty()) {
            return null;
        }

        GWB_Vacation_Coverage__c record = records[0];
        String entryMonthKey = normalizeMonthKeyFromText(record.Entry_Month_Year__c);
        String exitMonthKey = normalizeMonthKeyFromText(record.Exit_Month_Year__c);
        if (String.isBlank(entryMonthKey) || String.isBlank(exitMonthKey) || record.Vacation_Percent__c == null) {
            return null;
        }

        return new VacationCoverageConfigDto(record, entryMonthKey, exitMonthKey);
    }

    private static List<CommentDto> queryComments(Id gwbYearId) {
        List<CommentDto> comments = new List<CommentDto>();
        for (GWB_Budget_Comment__c commentRecord : [
            SELECT Id, Cell_Key__c, Table_Name__c, Row_Key__c, Row_Label__c, Month_Key__c,
                   Classification__c, Comment_Text__c, Value_Snapshot__c, CreatedDate,
                   Original_Created_Date__c, CreatedBy.Name
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c = :gwbYearId
            ORDER BY Original_Created_Date__c DESC, CreatedDate DESC
        ]) {
            comments.add(new CommentDto(commentRecord));
        }
        return comments;
    }

    private static String buildCommentCellKey(String tableName, String rowKey, String monthKey) {
        return String.join(new List<String>{
            String.isBlank(tableName) ? 'unknown' : tableName,
            String.isBlank(rowKey) ? 'unknown' : rowKey,
            String.isBlank(monthKey) ? 'unknown' : monthKey
        }, ':');
    }

    private static String normalizeMonthKeyFromText(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String normalized = value.trim().toLowerCase();
        Map<String, String> tokenToMonth = new Map<String, String>{
            'jan' => 'jan',
            'january' => 'jan',
            'feb' => 'feb',
            'february' => 'feb',
            'mar' => 'mar',
            'march' => 'mar',
            'apr' => 'apr',
            'april' => 'apr',
            'may' => 'may',
            'jun' => 'jun',
            'june' => 'jun',
            'jul' => 'jul',
            'july' => 'jul',
            'aug' => 'aug',
            'august' => 'aug',
            'sep' => 'sep',
            'sept' => 'sep',
            'september' => 'sep',
            'oct' => 'oct',
            'october' => 'oct',
            'nov' => 'nov',
            'november' => 'nov',
            'dec' => 'dec',
            'december' => 'dec'
        };

        for (String token : tokenToMonth.keySet()) {
            if (normalized.contains(token)) {
                return tokenToMonth.get(token);
            }
        }
        return null;
    }

    public class DynamicBudgetResponse {
        @AuraEnabled public DynamicBudgetHeader header;
        @AuraEnabled public VacationCoverageConfigDto vacationCoverageConfig;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public String statusMessage;
        @AuraEnabled public String configurationMessage;
        @AuraEnabled public Boolean isPlantAdminLikeUser;
        @AuraEnabled public Boolean isPlantScopedUser;
        @AuraEnabled public Boolean canUpdateStatus;
        @AuraEnabled public List<PicklistOption> statusOptions;
        @AuraEnabled public List<CommentDto> comments;
        @AuraEnabled public List<DynamicBudgetSection> sections;

        public DynamicBudgetResponse() {
            canEdit = false;
            configurationMessage = null;
            canUpdateStatus = false;
            statusOptions = new List<PicklistOption>();
            comments = new List<CommentDto>();
            sections = new List<DynamicBudgetSection>();
        }
    }

    public class DynamicBudgetHeader {
        @AuraEnabled public Id id;
        @AuraEnabled public String plantName;
        @AuraEnabled public String region;
        @AuraEnabled public String sector;
        @AuraEnabled public String version;
        @AuraEnabled public String mScheduleVersion;
        @AuraEnabled public String status;
        @AuraEnabled public String year;
        @AuraEnabled public String plantProgramName;
        @AuraEnabled public String productType;
        @AuraEnabled public String partType;
        @AuraEnabled public String functionalArea;
        @AuraEnabled public String targetTitle;

        public DynamicBudgetHeader() {}

        public DynamicBudgetHeader(GWB_Year__c source) {
            id = source.Id;
            plantName = source.Plant__r != null ? source.Plant__r.Name : null;
            region = source.Plant__r != null ? String.valueOf(source.Plant__r.Auth_Region__c) : null;
            sector = source.Sector__c;
            version = source.Version__c;
            mScheduleVersion = source.M_Schedule_Version__c;
            status = source.Status__c;
            year = source.Year__c;
            plantProgramName = source.Plant_Program__r != null ? source.Plant_Program__r.Name : null;
            productType = source.Plant_Program__r != null ? source.Plant_Program__r.Product_Type__c : null;
            partType = source.Plant_Sector__r != null ? source.Plant_Sector__r.Part_Type__c : null;
            functionalArea = source.Plant_Sector__r != null ? source.Plant_Sector__r.Functional_Area__c : null;
            targetTitle = source.Target_Title__c;
        }
    }

    public class DynamicBudgetSection {
        @AuraEnabled public String name;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public List<DynamicBudgetRow> rows;
    }

    public class DynamicBudgetRow {
        @AuraEnabled public String key;
        @AuraEnabled public String category;
        @AuraEnabled public String label;
        @AuraEnabled public String sourceValue;
        @AuraEnabled public String classification;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String sourceSection;
        @AuraEnabled public String lineType;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public String valueType;
        @AuraEnabled public Boolean editable;
        @AuraEnabled public Boolean fillForwardOnEdit;
        @AuraEnabled public String formulaKey;
        @AuraEnabled public String formulaTooltip;
        @AuraEnabled public String avgTotalTooltip;
        @AuraEnabled public Id recordId;
        @AuraEnabled public Map<String, Decimal> values;
    }

    public class RowInput {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String sourceValue { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String classification { get; set; }
        @AuraEnabled public String sourceType { get; set; }
        @AuraEnabled public String sourceSection { get; set; }
        @AuraEnabled public String valueType { get; set; }
        @AuraEnabled public Boolean editable { get; set; }
        @AuraEnabled public String lineType { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
        @AuraEnabled public String formulaKey { get; set; }
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public Map<String, Decimal> values { get; set; }
    }

    public class SaveResponse {
        @AuraEnabled public Integer savedRecordCount;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class CommentDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String cellKey;
        @AuraEnabled public String tableName;
        @AuraEnabled public String rowKey;
        @AuraEnabled public String rowLabel;
        @AuraEnabled public String monthKey;
        @AuraEnabled public String classification;
        @AuraEnabled public String commentText;
        @AuraEnabled public String valueSnapshot;
        @AuraEnabled public String authorName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdDateLabel;

        public CommentDto() {}

        public CommentDto(GWB_Budget_Comment__c commentRecord) {
            id = commentRecord.Id;
            cellKey = commentRecord.Cell_Key__c;
            tableName = commentRecord.Table_Name__c;
            rowKey = commentRecord.Row_Key__c;
            rowLabel = commentRecord.Row_Label__c;
            monthKey = commentRecord.Month_Key__c;
            classification = commentRecord.Classification__c;
            commentText = commentRecord.Comment_Text__c;
            valueSnapshot = commentRecord.Value_Snapshot__c;
            authorName = commentRecord.CreatedBy != null ? commentRecord.CreatedBy.Name : null;
            createdDate = commentRecord.Original_Created_Date__c;
            createdDateLabel = commentRecord.Original_Created_Date__c == null
                ? null
                : commentRecord.Original_Created_Date__c.format('MMM d, yyyy h:mm a');
        }
    }

    public class VacationCoverageConfigDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal vacationPercent;
        @AuraEnabled public String entryMonthKey;
        @AuraEnabled public String exitMonthKey;

        public VacationCoverageConfigDto() {}

        public VacationCoverageConfigDto(GWB_Vacation_Coverage__c record, String entryMonthKeyValue, String exitMonthKeyValue) {
            id = record.Id;
            vacationPercent = record.Vacation_Percent__c;
            entryMonthKey = entryMonthKeyValue;
            exitMonthKey = exitMonthKeyValue;
        }
    }
}