public with sharing class GwbBudgetWorkbenchController {
    private static final String LOG_PREFIX = 'GwbBudgetWorkbenchController';
    private static final String GENERIC_CREATE_ERROR = 'Unable to create the GWB draft right now. Please try again or contact your System Administrator.';
    private static final String GENERIC_SAVE_ERROR = 'Unable to save budget changes right now. Please try again or contact your System Administrator.';
    private static final String GENERIC_ROW_SAVE_ERROR = 'One or more budget rows failed to save. Please review the selected budget and row inputs.';
    private static final String GENERIC_STATUS_ERROR = 'Unable to update the budget state right now. Please try again or contact your System Administrator.';
    private static final String GENERIC_COMMENT_ERROR = 'Unable to save the comment right now. Please try again or contact your System Administrator.';
    private static final String READY_TO_PUBLISH_STATUS = 'Ready to Publish';
    private static final String DRAFT_STATUS = 'Draft';
    private static final String PUBLISHED_STATUS = 'Published';
    private static final String FINANCE_APPROVED_STATUS = 'Finance Approved';
    private static final String TARGET_NOT_FINANCE_APPROVED_ERROR = 'Target cannot be published as it is not in Finance Approved status';
    private static final String VIEW_ALL_GWB_PLANTS_PERMISSION = 'View_All_GWB_Plants';
    private static final Set<String> ALLOWED_DRIVER_OBJECTS = new Set<String>{ 'GWB_Month__c' };
    private static final Set<String> ALLOWED_EDITABLE_STATUSES = new Set<String>{ DRAFT_STATUS, READY_TO_PUBLISH_STATUS, 'Revised' };
    private static final Set<String> ALLOWED_STATUS_UPDATES = new Set<String>{ DRAFT_STATUS, READY_TO_PUBLISH_STATUS, PUBLISHED_STATUS, 'Revised' };
    private static final List<String> MONTH_KEYS = new List<String>{
        'prevDec', 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
    };
    private static final Map<String, String> SHARED_NUMBER_FIELDS = new Map<String, String>{
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
    private static final Map<String, String> SHARED_DECIMAL_FIELDS = new Map<String, String>{
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
    private static final Map<String, String> SHARED_PERCENT_FIELDS = new Map<String, String>{
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
    private static final Map<String, String> CLASSIFICATION_NUMBER_FIELDS = new Map<String, String>{
        'prevDec' => null,
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
    @TestVisible
    private static Boolean elevatedAccessOverride;

    @AuraEnabled(cacheable=true)
    public static BudgetOptionsResponse getBudgetOptions(Id plantId) {
        try {
            if (plantId == null) {
                return new BudgetOptionsResponse();
            }

            return buildBudgetOptionsResponse(plantId, null);
        } catch (Exception e) {
            logError('Error loading budget options', e);
            throw new AuraHandledException('Unable to load GWB budgets for this plant.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static BudgetOptionsResponse getBudgetContext(Id contextRecordId) {
        try {
            if (contextRecordId == null) {
                return new BudgetOptionsResponse();
            }

            if (contextRecordId.getSObjectType() == Plant__c.SObjectType) {
                return buildBudgetOptionsResponse(contextRecordId, null);
            }

            if (contextRecordId.getSObjectType() == GWB_Year__c.SObjectType) {
                GWB_Year__c budget = [
                    SELECT Id, Plant__c
                    FROM GWB_Year__c
                    WHERE Id = :contextRecordId
                    LIMIT 1
                ];
                // validateBudgetVisibility(budget);
                return buildBudgetOptionsResponse(budget.Plant__c, budget.Id);
            }

            throw new AuraHandledException('This page does not support the selected record type.');
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            logError('Error loading budget context', e);
            throw new AuraHandledException('Unable to load the GWB budget context for this page.');
        }
    }

    @AuraEnabled
    public static BudgetDetailResponse getBudgetDetail(Id gwbYearId) {
        try {
            if (gwbYearId == null) {
                return new BudgetDetailResponse();
            }

            GWB_Year__c header = [
                SELECT Id, Plant__c, Plant__r.Name, Sector__c, Status__c, Version__c, M_Schedule_Version__c, Year__c,
                       RecordType.DeveloperName
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];
            // validateBudgetVisibility(header);

            BudgetDetailResponse response = new BudgetDetailResponse();
            response.header = new BudgetHeader(header, canEditBudget(header));
            response.sharedRows = new List<RowDto>();
            response.driverRows = new List<RowDto>();
            response.comments = new List<CommentDto>();
            response.vacationCoverageConfig = loadVacationCoverageConfig(header.Plant__c, header.Sector__c, header.Year__c);
            response.publishedPrevDecBySharedKey = loadPublishedPrevDecBySharedKey(header);
            
            for (GWB_Month__c row : [
                SELECT Id, Section__c, Parameter__c, Classification__c,
                       Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c,
                       Prev_Dec_Decimal__c, Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                       Prev_Dec_Percent__c, Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c
                FROM GWB_Month__c
                WHERE GWB_Year__c = :gwbYearId
                AND Parameter__c != null
            ]) {
                response.sharedRows.add(toSharedRowDto(row));
            }
            response.driverRows.addAll(toDriverRowDtos('GWB_Month__c', queryDriverRows(gwbYearId), 'OTS'));
            response.driverRows.addAll(toDriverRowDtos('GWB_Month__c', queryDriverRows(gwbYearId), 'Skilled'));
            response.driverRows.addAll(toDriverRowDtos('GWB_Month__c', queryDriverRows(gwbYearId), 'Salaried'));
            response.comments.addAll(queryComments(gwbYearId));
            return response;
        } catch (Exception e) {
            logError('Error loading budget detail', e);
            throw new AuraHandledException('Unable to load the selected GWB budget.');
        }
    }

    @AuraEnabled
    public static BudgetOption createBudgetDraft(Id plantId, String year, String sector, String version) {
        try {
            if (plantId == null || String.isBlank(year) || String.isBlank(sector) || String.isBlank(version)) {
                throw new AuraHandledException('Plant, year, sector, and version are required to create a draft.');
            }

            // enforceBudgetEditPermission();

            String previousYear = String.valueOf(Integer.valueOf(year) - 1);

            List<Plant__c> lockedPlants = [
                SELECT Id
                FROM Plant__c
                WHERE Id = :plantId
                LIMIT 1
                FOR UPDATE
            ];

            List<GWB_Year__c> existing = [
                SELECT Id, Plant__c, Sector__c, Status__c, Version__c, Year__c, Previous_Year_GWB__c, Plant_Sector__c,
                       RecordType.DeveloperName
                FROM GWB_Year__c
                WHERE Plant__c = :plantId
                AND Year__c = :year
                AND Sector__c = :sector
                AND Version__c = :version
                LIMIT 1
            ];

            if (!existing.isEmpty()) {
                return new BudgetOption(existing[0]);
            }

            Id budgetRecordTypeId = getRecordTypeId('Budget');
            Id previousYearGwbId = findPreviousPublishedBudgetId(plantId, sector, previousYear);
            Id plantSectorId = findPlantSectorId(plantId, sector);

            GWB_Year__c draft = new GWB_Year__c(
                Plant__c = plantId,
                Year__c = year,
                Sector__c = sector,
                Version__c = version,
                Status__c = DRAFT_STATUS,
                Previous_Year_GWB__c = previousYearGwbId,
                Plant_Sector__c = plantSectorId,
                RecordTypeId = budgetRecordTypeId
            );
            insert draft;

            GwbBudgetDraftSeedService.seedDraft(draft.Id, previousYearGwbId, plantId, sector, year, version);

            draft = [
                SELECT Id, Plant__c, Sector__c, Status__c, Version__c, Year__c, Previous_Year_GWB__c, Plant_Sector__c,
                       RecordType.DeveloperName
                FROM GWB_Year__c
                WHERE Id = :draft.Id
                LIMIT 1
            ];

            return new BudgetOption(draft);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            logError('Error creating budget draft', e);
            throw new AuraHandledException(GENERIC_CREATE_ERROR);
        }
    }

    @AuraEnabled
    public static SaveResponse saveBudgetRows(Id gwbYearId, String sharedRowsJson, String driverRowsJson) {
        Savepoint sp = Database.setSavepoint();
        try {
            validateSaveRequest(gwbYearId);
            List<RowInput> sharedRows = parseRowInputs(sharedRowsJson);
            List<RowInput> driverRows = parseRowInputs(driverRowsJson);
            System.debug(LoggingLevel.WARN, LOG_PREFIX + ' | saveBudgetRows request | gwbYearId=' + gwbYearId +
                ' | sharedRows=' + summarizeRowInputs(sharedRows) +
                ' | driverRows=' + summarizeRowInputs(driverRows));

            GWB_Year__c header = [
                SELECT Id, Plant__c, Sector__c, Version__c, M_Schedule_Version__c, Year__c, Status__c
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];
            // validateBudgetVisibility(header);
            validateBudgetIsEditable(header);

            validateRowPayloads(gwbYearId, sharedRows, driverRows);

            Map<String, List<SObject>> insertsByType = new Map<String, List<SObject>>();
            Map<String, List<SObject>> updatesByType = new Map<String, List<SObject>>();

            if (sharedRows != null) {
                for (RowInput row : sharedRows) {
                    SObject record = buildSharedRow(row, header);
                    System.debug(LoggingLevel.WARN, LOG_PREFIX + ' | saveBudgetRows built shared row | ' + summarizeSObject(record));
                    if (row.recordId == null) {
                        addToDmlBucket(insertsByType, record);
                    } else {
                        addToDmlBucket(updatesByType, record);
                    }
                }
            }

            if (driverRows != null) {
                for (RowInput row : driverRows) {
                    SObject record = buildDriverRow(row, header);
                    System.debug(LoggingLevel.WARN, LOG_PREFIX + ' | saveBudgetRows built driver row | ' + summarizeSObject(record));
                    if (row.recordId == null) {
                        addToDmlBucket(insertsByType, record);
                    } else {
                        addToDmlBucket(updatesByType, record);
                    }
                }
            }

            Integer updateCount = 0;
            Integer insertCount = 0;
            for (List<SObject> updates : updatesByType.values()) {
                if (updates.isEmpty()) {
                    continue;
                }
                updateCount += updates.size();
                processSaveResults(Database.update(updates, false), 'update');
            }

            for (List<SObject> inserts : insertsByType.values()) {
                if (inserts.isEmpty()) {
                    continue;
                }
                insertCount += inserts.size();
                processSaveResults(Database.insert(inserts, false), 'insert');
            }

            SaveResponse response = new SaveResponse();
            response.success = true;
            response.message = 'Budget changes saved.';
            response.updatedCount = updateCount + insertCount;
            return response;
        } catch (AuraHandledException ahe) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' | Save failed with handled error | ' + ahe.getMessage());
            throw ahe;
        } catch (Exception e) {
            Database.rollback(sp);
            logError('Error saving budget rows', e);
            throw new AuraHandledException(GENERIC_SAVE_ERROR);
        }
    }

    @AuraEnabled
    public static BudgetHeader updateBudgetState(Id gwbYearId, String nextStatus) {
        try {
            if (gwbYearId == null) {
                throw new AuraHandledException('A valid GWB budget must be selected before updating its state.');
            }
            // enforceBudgetEditPermission();

            GWB_Year__c budget = [
                SELECT Id, Plant__c, Plant__r.Name, Sector__c, Status__c, Version__c, M_Schedule_Version__c, Year__c,
                       RecordType.DeveloperName
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];

            if (nextStatus == PUBLISHED_STATUS && budget.Status__c != FINANCE_APPROVED_STATUS) {
                throw new AuraHandledException(TARGET_NOT_FINANCE_APPROVED_ERROR);
            }

            budget.Status__c = String.isBlank(nextStatus) ? budget.Status__c : nextStatus;
            update budget;

            return new BudgetHeader(budget, canEditBudget(budget));
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            logError('Error updating budget state', e);
            throw new AuraHandledException(String.isBlank(e.getMessage()) ? GENERIC_STATUS_ERROR : e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getBudgetStatusOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : GWB_Year__c.Status__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
        }
        return options;
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
                SELECT Id, Plant__r.Name, Status__c
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];
            // validateBudgetVisibility(header);
            validateBudgetIsEditable(header);

            GWB_Budget_Comment__c commentRecord;
            if (commentId != null) {
                commentRecord = [
                    SELECT Id, GWB_Year__c
                    FROM GWB_Budget_Comment__c
                    WHERE Id = :commentId
                    LIMIT 1
                ];
                // if (commentRecord.GWB_Year__c != gwbYearId) {
                //     throw new AuraHandledException('The selected comment does not belong to this budget.');
                // }

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
            logError('Error saving budget comment', e);
            throw new AuraHandledException(GENERIC_COMMENT_ERROR);
        }
    }

    private static List<SObject> queryDriverRows(Id gwbYearId) {
        return [
            SELECT Id, Driver__c, Classification__c, Data_Point_Value__c, Year__c, Plant__c, Sector__c,
                   Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :gwbYearId
            AND Driver__c != null
        ];
    }

    private static BudgetOptionsResponse buildBudgetOptionsResponse(Id plantId, Id preferredBudgetId) {
        Boolean canAccessAllBudgets = hasElevatedBudgetAccess();
        List<GWB_Year__c> budgets = [
            SELECT Id, Plant__c, Sector__c, Status__c, Version__c, Year__c, RecordType.DeveloperName
            FROM GWB_Year__c
            WHERE Plant__c = :plantId
            ORDER BY Year__c DESC, LastModifiedDate DESC
        ];

        BudgetOptionsResponse response = new BudgetOptionsResponse();
        response.plantId = plantId;
        response.canEdit = canAccessAllBudgets;
        response.options = new List<BudgetOption>();

        Id selectedBudgetId = preferredBudgetId;
        for (GWB_Year__c budget : budgets) {
            response.options.add(new BudgetOption(budget));
            if (selectedBudgetId == null && budget.Status__c == DRAFT_STATUS) {
                selectedBudgetId = budget.Id;
            }
        }

        if (selectedBudgetId == null && !budgets.isEmpty()) {
            selectedBudgetId = budgets[0].Id;
        }

        response.selectedBudgetId = selectedBudgetId;
        return response;
    }

    private static RowDto toSharedRowDto(GWB_Month__c row) {
        RowDto dto = new RowDto();
        dto.recordId = row.Id;
        dto.objectApiName = 'GWB_Month__c';
        dto.section = row.Section__c;
        dto.parameter = row.Parameter__c;
        dto.classification = row.Classification__c;
        dto.valueType = inferSharedValueType(row);
        dto.values = extractValues(row, dto.valueType);
        System.debug(LoggingLevel.WARN, LOG_PREFIX + ' | toSharedRowDto | recordId=' + row.Id + ' | parameter=' + row.Parameter__c + ' | classification=' + row.Classification__c + ' | valueType=' + dto.valueType + ' | values=' + dto.values);
        return dto;
    }

    private static List<RowDto> toDriverRowDtos(String objectApiName, List<SObject> rows, String fallbackClassification) {
        List<RowDto> results = new List<RowDto>();
        for (SObject row : rows) {
            RowDto dto = new RowDto();
            dto.recordId = (Id) row.get('Id');
            dto.objectApiName = objectApiName;
            dto.driver = (String) row.get('Driver__c');
            dto.classification = String.isBlank((String) row.get('Classification__c')) ? fallbackClassification : normalizeDriverClassification((String) row.get('Classification__c'), fallbackClassification);
            dto.valueType = 'number';
            dto.values = extractDriverValues(row);
            results.add(dto);
        }
        return results;
    }

    private static String inferSharedValueType(GWB_Month__c row) {
        if (row.Prev_Dec_Decimal__c != null || row.Jan_Decimal__c != null || row.Feb_Decimal__c != null || row.Mar_Decimal__c != null || row.Apr_Decimal__c != null || row.May_Decimal__c != null || row.Jun_Decimal__c != null || row.Jul_Decimal__c != null || row.Aug_Decimal__c != null || row.Sep_Decimal__c != null || row.Oct_Decimal__c != null || row.Nov_Decimal__c != null || row.Dec_Decimal__c != null) {
            return 'decimal';
        }
        if (row.Prev_Dec_Percent__c != null || row.Jan_Percent__c != null || row.Feb_Percent__c != null || row.Mar_Percent__c != null || row.Apr_Percent__c != null || row.May_Percent__c != null || row.Jun_Percent__c != null || row.Jul_Percent__c != null || row.Aug_Percent__c != null || row.Sep_Percent__c != null || row.Oct_Percent__c != null || row.Nov_Percent__c != null || row.Dec_Percent__c != null) {
            return 'percent';
        }
        return 'number';
    }

    private static Map<String, Decimal> extractValues(GWB_Month__c row, String valueType) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        Map<String, String> fieldMap = valueType == 'decimal' ? SHARED_DECIMAL_FIELDS : valueType == 'percent' ? SHARED_PERCENT_FIELDS : SHARED_NUMBER_FIELDS;
        for (String monthKey : MONTH_KEYS) {
            values.put(monthKey, (Decimal) row.get(fieldMap.get(monthKey)));
        }
        return values;
    }

    private static Map<String, Decimal> extractDriverValues(SObject row) {
        Map<String, Decimal> values = new Map<String, Decimal>{ 'prevDec' => 0 };
        for (String monthKey : MONTH_KEYS) {
            String fieldName = CLASSIFICATION_NUMBER_FIELDS.get(monthKey);
            if (fieldName != null) {
                values.put(monthKey, (Decimal) row.get(fieldName));
            }
        }
        return values;
    }

    private static Map<String, Decimal> loadPublishedPrevDecBySharedKey(GWB_Year__c budget) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        if (budget == null || budget.Plant__c == null || String.isBlank(budget.Sector__c) || String.isBlank(budget.Year__c)) {
            return result;
        }

        Integer currentYear;
        try {
            currentYear = Integer.valueOf(budget.Year__c);
        } catch (Exception ex) {
            return result;
        }

        Id previousPublishedId = findLatestPublishedYearId(
            budget.Plant__c,
            budget.Sector__c,
            String.valueOf(currentYear - 1)
        );
        if (previousPublishedId == null) {
            return result;
        }

        for (GWB_Month__c row : [
            SELECT Id, Parameter__c, Classification__c,
                   Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c,
                   Prev_Dec_Decimal__c, Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                   Prev_Dec_Percent__c, Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :previousPublishedId
            AND Parameter__c != null
        ]) {
            result.put(
                buildSharedPrevDecKey(row.Parameter__c, row.Classification__c),
                getSharedPrevDecBaseline(row, inferSharedValueType(row))
            );
        }

        return result;
    }

    private static String buildSharedPrevDecKey(String parameter, String classification) {
        return String.valueOf(parameter == null ? '' : parameter) + '|' +
            String.valueOf(classification == null ? '' : classification);
    }

    private static Decimal getSharedPrevDecBaseline(GWB_Month__c row, String valueType) {
        if (row == null) {
            return 0;
        }

        if (valueType == 'decimal') {
            return row.Dec_Decimal__c != null
                ? row.Dec_Decimal__c
                : (row.Prev_Dec_Decimal__c != null ? row.Prev_Dec_Decimal__c : 0);
        }
        if (valueType == 'percent') {
            return row.Dec_Percent__c != null
                ? row.Dec_Percent__c
                : (row.Prev_Dec_Percent__c != null ? row.Prev_Dec_Percent__c : 0);
        }
        return row.Dec_Number__c != null
            ? row.Dec_Number__c
            : (row.Prev_Dec_Number__c != null ? row.Prev_Dec_Number__c : 0);
    }

    private static SObject buildSharedRow(RowInput row, GWB_Year__c header) {
        GWB_Month__c record = row.recordId == null ? new GWB_Month__c() : new GWB_Month__c(Id = row.recordId);
        if (row.recordId == null) {
            record.GWB_Year__c = header.Id;
        }
        record.Section__c = row.section;
        record.Parameter__c = row.parameter;
        record.Classification__c = row.classification;

        Map<String, String> fieldMap = row.valueType == 'decimal' ? SHARED_DECIMAL_FIELDS : row.valueType == 'percent' ? SHARED_PERCENT_FIELDS : SHARED_NUMBER_FIELDS;
        clearSharedValueFields(record);
        for (String monthKey : MONTH_KEYS) {
            if (row.values != null && row.values.containsKey(monthKey)) {
                record.put(fieldMap.get(monthKey), row.values.get(monthKey));
            }
        }
        System.debug(LoggingLevel.WARN, LOG_PREFIX + ' | buildSharedRow | input=' + summarizeRowInput(row) + ' | built=' + summarizeSObject(record));
        return record;
    }

    private static SObject buildDriverRow(RowInput row, GWB_Year__c header) {
        SObject record = row.recordId == null ? Schema.getGlobalDescribe().get(row.objectApiName).newSObject() : Schema.getGlobalDescribe().get(row.objectApiName).newSObject(row.recordId);
        if (row.recordId == null) {
            record.put('GWB_Year__c', header.Id);
        }
        record.put('Driver__c', normalizeDriverValue(row.driver));
        record.put('Classification__c', toDriverClassificationValue(row.classification));
        record.put('Plant__c', header.Plant__c);
        record.put('Sector__c', header.Sector__c);
        record.put('Year__c', header.Year__c);
        record.put('Data_Point_Value__c', String.isBlank(header.M_Schedule_Version__c) ? header.Version__c : header.M_Schedule_Version__c);

        for (String monthKey : MONTH_KEYS) {
            String fieldName = CLASSIFICATION_NUMBER_FIELDS.get(monthKey);
            if (fieldName != null && row.values != null && row.values.containsKey(monthKey)) {
                record.put(fieldName, row.values.get(monthKey));
            }
        }
        return record;
    }

    private static String normalizeDriverValue(String driver) {
        if (driver == 'Additional ST Adjustment' || driver == 'Additional Straight Time Hours Adjustment') {
            return 'Additional ST Adjust';
        }
        return driver;
    }

    private static String normalizeDriverClassification(String value, String fallbackClassification) {
        if (String.isBlank(value)) {
            return fallbackClassification;
        }
        if (value == 'OST') {
            return 'OTS';
        }
        if (value == 'SK') {
            return 'Skilled';
        }
        if (value == 'SAL') {
            return 'Salaried';
        }
        return value;
    }

    private static List<RowInput> parseRowInputs(String rowsJson) {
        List<RowInput> results = new List<RowInput>();
        if (String.isBlank(rowsJson)) {
            return results;
        }

        Object raw = JSON.deserializeUntyped(rowsJson);
        if (!(raw instanceof List<Object>)) {
            return results;
        }

        for (Object entry : (List<Object>) raw) {
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> rowMap = (Map<String, Object>) entry;
            RowInput row = new RowInput();
            row.recordId = rowMap.containsKey('recordId') && rowMap.get('recordId') != null ? (Id) rowMap.get('recordId') : null;
            row.objectApiName = (String) rowMap.get('objectApiName');
            row.section = (String) rowMap.get('section');
            row.parameter = (String) rowMap.get('parameter');
            row.driver = (String) rowMap.get('driver');
            row.classification = (String) rowMap.get('classification');
            row.valueType = (String) rowMap.get('valueType');
            row.values = parseDecimalMap(rowMap.get('values'));
            results.add(row);
        }

        return results;
    }

    private static Map<String, Decimal> parseDecimalMap(Object rawValues) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        if (!(rawValues instanceof Map<String, Object>)) {
            return values;
        }

        Map<String, Object> rawMap = (Map<String, Object>) rawValues;
        for (String key : rawMap.keySet()) {
            Object rawValue = rawMap.get(key);
            if (rawValue == null) {
                values.put(key, null);
            } else if (rawValue instanceof Decimal) {
                values.put(key, (Decimal) rawValue);
            } else if (rawValue instanceof Integer) {
                values.put(key, Decimal.valueOf(String.valueOf(rawValue)));
            } else if (rawValue instanceof Long) {
                values.put(key, Decimal.valueOf(String.valueOf(rawValue)));
            } else if (rawValue instanceof Double) {
                values.put(key, Decimal.valueOf(String.valueOf(rawValue)));
            } else {
                values.put(key, Decimal.valueOf(String.valueOf(rawValue)));
            }
        }
        return values;
    }

    private static String summarizeRowInputs(List<RowInput> rows) {
        if (rows == null) {
            return 'null';
        }
        List<String> items = new List<String>();
        for (RowInput row : rows) {
            items.add(summarizeRowInput(row));
        }
        return String.join(items, ' || ');
    }

    private static String summarizeRowInput(RowInput row) {
        if (row == null) {
            return 'null';
        }
        return 'recordId=' + row.recordId +
            ', objectApiName=' + row.objectApiName +
            ', section=' + row.section +
            ', parameter=' + row.parameter +
            ', driver=' + row.driver +
            ', classification=' + row.classification +
            ', valueType=' + row.valueType +
            ', values=' + row.values;
    }

    private static String summarizeSObject(SObject record) {
        if (record == null) {
            return 'null';
        }
        return JSON.serialize(record);
    }

    private static String toDriverClassificationValue(String label) {
        return normalizeDriverClassification(label, 'OTS');
    }

    private static void validateSaveRequest(Id gwbYearId) {
        if (gwbYearId == null) {
            throw new AuraHandledException('A valid GWB budget must be selected before saving.');
        }
    }

    private static void validateBudgetVisibility(GWB_Year__c budget) {
        if (budget == null) {
            throw new AuraHandledException('The selected GWB budget could not be found.');
        }
    }

    private static void validateBudgetIsEditable(GWB_Year__c budget) {
        if (!canEditBudget(budget)) {
            throw new AuraHandledException('This budget is read-only for your access level or current status.');
        }
    }

    private static Boolean canEditBudget(GWB_Year__c budget) {
        return budget != null && budget.Status__c != PUBLISHED_STATUS;
    }

    private static void enforceBudgetEditPermission() {
        if (!hasElevatedBudgetAccess()) {
            throw new AuraHandledException('You do not have access to edit this budget.');
        }
    }

    private static Boolean hasElevatedBudgetAccess() {
        if (Test.isRunningTest() && elevatedAccessOverride != null) {
            return elevatedAccessOverride;
        }
        return FeatureManagement.checkPermission(VIEW_ALL_GWB_PLANTS_PERMISSION);
    }

    private static Id findPreviousPublishedBudgetId(Id plantId, String sector, String previousYear) {
        List<GWB_Year__c> previousBudgets = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plantId
            AND Sector__c = :sector
            AND Year__c = :previousYear
            AND Status__c = :PUBLISHED_STATUS
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (previousBudgets.isEmpty()) {
            throw new AuraHandledException('No published current-year GWB record was found for the selected Plant and Sector.');
        }
        return previousBudgets[0].Id;
    }

    private static Id findLatestPublishedYearId(Id plantId, String sector, String yearValue) {
        if (plantId == null || String.isBlank(sector) || String.isBlank(yearValue)) {
            return null;
        }

        List<GWB_Year__c> publishedRecords = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plantId
            AND Sector__c = :sector
            AND Year__c = :yearValue
            AND Status__c = :PUBLISHED_STATUS
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return publishedRecords.isEmpty() ? null : publishedRecords[0].Id;
    }

    private static Id findPlantSectorId(Id plantId, String sector) {
        List<Plant_Sector__c> plantSectors = [
            SELECT Id
            FROM Plant_Sector__c
            WHERE Plant__c = :plantId
            AND Auth_Sector__c = :sector
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return plantSectors.isEmpty() ? null : plantSectors[0].Id;
    }

    private static Id getRecordTypeId(String developerName) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = :developerName
            LIMIT 1
        ];

        if (recordTypes.isEmpty()) {
            throw new AuraHandledException('The required GWB Year record type could not be found: ' + developerName);
        }

        return recordTypes[0].Id;
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

    private static String buildCommentCellKey(String tableName, String rowKey, String monthKey) {
        return String.join(new List<String>{
            String.isBlank(tableName) ? 'unknown' : tableName,
            String.isBlank(rowKey) ? 'unknown' : rowKey,
            String.isBlank(monthKey) ? 'unknown' : monthKey
        }, ':');
    }

    private static void validateRowPayloads(Id gwbYearId, List<RowInput> sharedRows, List<RowInput> driverRows) {
        Set<Id> sharedIds = new Set<Id>();
        Map<String, Set<Id>> driverIdsByObject = new Map<String, Set<Id>>();

        if (sharedRows != null) {
            for (RowInput row : sharedRows) {
                if (!String.isBlank(row.objectApiName) && row.objectApiName != 'GWB_Month__c') {
                    throw new AuraHandledException('An invalid shared budget row was submitted.');
                }
                if (row.recordId != null) {
                    sharedIds.add(row.recordId);
                }
            }
        }

        if (driverRows != null) {
            for (RowInput row : driverRows) {
                if (String.isBlank(row.objectApiName) || !ALLOWED_DRIVER_OBJECTS.contains(row.objectApiName)) {
                    throw new AuraHandledException('An invalid driver budget row was submitted.');
                }

                if (row.recordId != null) {
                    if (!driverIdsByObject.containsKey(row.objectApiName)) {
                        driverIdsByObject.put(row.objectApiName, new Set<Id>());
                    }
                    driverIdsByObject.get(row.objectApiName).add(row.recordId);
                }
            }
        }

        Map<Id, GWB_Month__c> sharedById = sharedIds.isEmpty()
            ? new Map<Id, GWB_Month__c>()
            : new Map<Id, GWB_Month__c>([
                SELECT Id
                FROM GWB_Month__c
                WHERE Id IN :sharedIds
                AND GWB_Year__c = :gwbYearId
            ]);

        Map<String, Set<Id>> validDriverIdsByObject = new Map<String, Set<Id>>();
        for (String objectApiName : driverIdsByObject.keySet()) {
            validDriverIdsByObject.put(objectApiName, queryDriverRowIds(objectApiName, gwbYearId, driverIdsByObject.get(objectApiName)));
        }

        if (sharedRows != null) {
            for (RowInput row : sharedRows) {
                if (row.recordId != null && !sharedById.containsKey(row.recordId)) {
                    throw new AuraHandledException('One or more shared budget rows are no longer valid for the selected budget.');
                }
            }
        }

        if (driverRows != null) {
            for (RowInput row : driverRows) {
                if (row.recordId == null) {
                    continue;
                }

                Set<Id> validIds = validDriverIdsByObject.get(row.objectApiName);
                if (validIds == null || !validIds.contains(row.recordId)) {
                    throw new AuraHandledException('One or more driver budget rows are no longer valid for the selected budget.');
                }
            }
        }
    }

    private static Set<Id> queryDriverRowIds(String objectApiName, Id gwbYearId, Set<Id> driverIds) {
        if (driverIds == null || driverIds.isEmpty()) {
            return new Set<Id>();
        }

        String soql = 'SELECT Id FROM ' + objectApiName + ' WHERE Id IN :driverIds AND GWB_Year__c = :gwbYearId';
        Set<Id> validIds = new Set<Id>();
        for (SObject record : Database.query(soql)) {
            validIds.add((Id) record.get('Id'));
        }
        return validIds;
    }

    private static void addToDmlBucket(Map<String, List<SObject>> bucket, SObject record) {
        String objectApiName = record.getSObjectType().getDescribe().getName();
        if (!bucket.containsKey(objectApiName)) {
            bucket.put(objectApiName, new List<SObject>());
        }
        bucket.get(objectApiName).add(record);
    }

    private static void clearSharedValueFields(GWB_Month__c record) {
        clearFields(record, SHARED_NUMBER_FIELDS);
        clearFields(record, SHARED_DECIMAL_FIELDS);
        clearFields(record, SHARED_PERCENT_FIELDS);
    }

    private static void clearFields(SObject record, Map<String, String> fieldMap) {
        for (String fieldName : fieldMap.values()) {
            if (fieldName != null) {
                record.put(fieldName, null);
            }
        }
    }

    private static void processSaveResults(List<Database.SaveResult> results, String operation) {
        List<String> errors = new List<String>();
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                continue;
            }

            for (Database.Error error : result.getErrors()) {
                errors.add(operation + ': ' + error.getStatusCode() + ' - ' + error.getMessage());
            }
        }

        if (!errors.isEmpty()) {
            logErrorMessage('Save result failure | ' + operation + ' | ' + String.join(errors, ' | '));
            throw new AuraHandledException(GENERIC_ROW_SAVE_ERROR);
        }
    }

    private static void logError(String message, Exception e) {
        System.debug(LoggingLevel.ERROR,
            LOG_PREFIX + ' | ' + message + ' | ' + e.getTypeName() + ' | ' + e.getMessage() + ' | ' + e.getStackTraceString());
    }

    private static void logErrorMessage(String message) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' | ' + message);
    }

    public class BudgetOptionsResponse {
        @AuraEnabled public Id plantId;
        @AuraEnabled public Id selectedBudgetId;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public List<BudgetOption> options = new List<BudgetOption>();
    }

    public class BudgetOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String year;
        @AuraEnabled public String sector;
        @AuraEnabled public String version;
        @AuraEnabled public String status;
        @AuraEnabled public String recordTypeDeveloperName;
        public BudgetOption() {}

        public BudgetOption(GWB_Year__c budget) {
            id = budget.Id;
            year = budget.Year__c;
            sector = budget.Sector__c;
            version = budget.Version__c;
            status = budget.Status__c;
            recordTypeDeveloperName = budget.RecordType != null ? budget.RecordType.DeveloperName : null;
            label = String.join(new List<String>{
                String.isBlank(budget.Year__c) ? 'Unknown Year' : budget.Year__c,
                String.isBlank(budget.Sector__c) ? 'No Sector' : budget.Sector__c,
                String.isBlank(budget.Version__c) ? 'No Version' : budget.Version__c,
                String.isBlank(budget.Status__c) ? 'No Status' : budget.Status__c
            }, ' · ');
        }
    }

    public class BudgetHeader {
        @AuraEnabled public Id id;
        @AuraEnabled public String plantName;
        @AuraEnabled public String sector;
        @AuraEnabled public String version;
        @AuraEnabled public String mScheduleVersion;
        @AuraEnabled public String status;
        @AuraEnabled public String year;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String currentUserName;
        public BudgetHeader() {}

        public BudgetHeader(GWB_Year__c budget, Boolean canEditBudget) {
            id = budget.Id;
            plantName = budget.Plant__r != null ? budget.Plant__r.Name : null;
            sector = budget.Sector__c;
            version = budget.Version__c;
            mScheduleVersion = budget.M_Schedule_Version__c;
            status = budget.Status__c;
            year = budget.Year__c;
            canEdit = canEditBudget;
            recordTypeDeveloperName = budget.RecordType != null ? budget.RecordType.DeveloperName : null;
            currentUserName = UserInfo.getName();
        }
    }

    public class BudgetDetailResponse {
        @AuraEnabled public BudgetHeader header;
        @AuraEnabled public List<RowDto> sharedRows = new List<RowDto>();
        @AuraEnabled public List<RowDto> driverRows = new List<RowDto>();
        @AuraEnabled public List<CommentDto> comments = new List<CommentDto>();
        @AuraEnabled public VacationCoverageConfigDto vacationCoverageConfig;
        @AuraEnabled public Map<String, Decimal> publishedPrevDecBySharedKey = new Map<String, Decimal>();
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

    public class RowDto {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String section;
        @AuraEnabled public String parameter;
        @AuraEnabled public String driver;
        @AuraEnabled public String classification;
        @AuraEnabled public String valueType;
        @AuraEnabled public Map<String, Decimal> values;
    }

    public class RowInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String section;
        @AuraEnabled public String parameter;
        @AuraEnabled public String driver;
        @AuraEnabled public String classification;
        @AuraEnabled public String valueType;
        @AuraEnabled public Map<String, Decimal> values;
    }

    public class SaveResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer updatedCount;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption() {}

        public PicklistOption(String labelValue, String actualValue) {
            label = labelValue;
            value = actualValue;
        }
    }

    public class CommentInput {
        @AuraEnabled public String tableName;
        @AuraEnabled public String rowKey;
        @AuraEnabled public String rowLabel;
        @AuraEnabled public String monthKey;
        @AuraEnabled public String classification;
        @AuraEnabled public String commentText;
        @AuraEnabled public String valueSnapshot;
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
}