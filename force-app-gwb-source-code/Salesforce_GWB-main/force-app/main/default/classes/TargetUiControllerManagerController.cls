public with sharing class TargetUiControllerManagerController {
    private static final String CMDT_TYPE_API_NAME = 'Target_UI_Controller__mdt';
    private static final String CMDT_FULLNAME_PREFIX = 'Target_UI_Controller__mdt.';
    private static final String ALL_SECTORS_VALUE = '__ALL__';

    @AuraEnabled(cacheable=true)
    public static ManagerDataResponse getManagerData(String sectorFilter, String searchTerm, Boolean activeOnly) {
        List<Target_UI_Controller__mdt> records = [
            SELECT DeveloperName, MasterLabel, Sector__c, Section_Name__c, Section_Sequence__c, Category__c,
                Source_Section__c, Parameter_Driver__c, Source_Value__c, Classification__c, Source_Type__c,
                UI_Line_Type__c, UI_Sequence__c, Internal_Key__c, Value_Type__c, Is_Editable__c, Is_Active__c,
                Fill_Forward_On_Edit__c, Formula_Key__c, Formula_Tooltip__c
            FROM Target_UI_Controller__mdt
            ORDER BY Sector__c ASC, Category__c ASC, UI_Sequence__c ASC, MasterLabel ASC
        ];

        ManagerDataResponse response = new ManagerDataResponse();
        response.totalCount = records.size();
        response.rows = new List<TargetUiRow>();
        response.editorOptions = buildEditorOptions(records);

        String normalizedSector = normalizeSectorFilter(sectorFilter);
        String normalizedSearch = normalizeSearch(searchTerm);
        Boolean onlyActive = activeOnly == true;

        Map<String, List<TargetUiRow>> rowsBySortKey = new Map<String, List<TargetUiRow>>();
        List<String> sortKeys = new List<String>();
        for (Target_UI_Controller__mdt record : records) {
            if (!matchesSector(record, normalizedSector)) {
                continue;
            }
            if (onlyActive && record.Is_Active__c != true) {
                continue;
            }
            if (!matchesSearch(record, normalizedSearch)) {
                continue;
            }

            TargetUiRow row = toRow(record);
            String sortKey = buildManagerSortKey(row);
            if (!rowsBySortKey.containsKey(sortKey)) {
                rowsBySortKey.put(sortKey, new List<TargetUiRow>());
                sortKeys.add(sortKey);
            }
            rowsBySortKey.get(sortKey).add(row);
        }

        sortKeys.sort();
        Integer displayOrder = 1;
        for (String sortKey : sortKeys) {
            for (TargetUiRow row : rowsBySortKey.get(sortKey)) {
                row.displayOrder = displayOrder;
                response.rows.add(row);
                displayOrder += 1;
            }
        }

        response.filteredCount = response.rows.size();
        return response;
    }

    @AuraEnabled
    public static DeployRequestResult upsertTargetUiControllerRecord(UpsertRecordRequest requestPayload) {
        return upsertTargetUiControllerRecords(new List<UpsertRecordRequest>{ requestPayload });
    }

    @AuraEnabled
    public static DeployRequestResult upsertTargetUiControllerRecords(List<UpsertRecordRequest> requestPayloads) {
        if (requestPayloads == null || requestPayloads.isEmpty()) {
            throw new AuraHandledException('Provide at least one record payload.');
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        List<String> savedDeveloperNames = new List<String>();
        List<String> savedLabels = new List<String>();

        for (UpsertRecordRequest requestPayload : requestPayloads) {
        validateRequest(requestPayload);

        String developerName = sanitizeDeveloperName(requestPayload.developerName);
        if (String.isBlank(developerName)) {
            developerName = generateDeveloperName(requestPayload);
        }

        String label = String.isBlank(requestPayload.masterLabel)
            ? buildDefaultLabel(requestPayload)
            : requestPayload.masterLabel.trim();

        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = CMDT_FULLNAME_PREFIX + developerName;
        metadataRecord.label = label;
        metadataRecord.values = buildMetadataValues(requestPayload);
            container.addMetadata(metadataRecord);
            savedDeveloperNames.add(developerName);
            savedLabels.add(label);
        }

        if (Test.isRunningTest()) {
            DeployRequestResult fakeResult = new DeployRequestResult();
            fakeResult.deploymentId = 'TEST-' + String.valueOf(DateTime.now().getTime());
            fakeResult.developerName = savedDeveloperNames[0];
            fakeResult.masterLabel = savedLabels[0];
            fakeResult.recordCount = savedDeveloperNames.size();
            fakeResult.queued = true;
            fakeResult.message = 'Queued metadata deployment.';
            return fakeResult;
        }

        Id deploymentId = Metadata.Operations.enqueueDeployment(
            container,
            new TargetUiControllerDeployCallback()
        );

        DeployRequestResult response = new DeployRequestResult();
        response.deploymentId = String.valueOf(deploymentId);
        response.developerName = savedDeveloperNames[0];
        response.masterLabel = savedLabels[0];
        response.recordCount = savedDeveloperNames.size();
        response.queued = true;
        response.message = 'Queued metadata deployment.';
        return response;
    }

    @AuraEnabled
    public static DeployStatusResult getDeploymentStatus(String deploymentId) {
        if (String.isBlank(deploymentId)) {
            throw new AuraHandledException('Deployment id is required.');
        }

        if (Test.isRunningTest()) {
            DeployStatusResult fakeStatus = new DeployStatusResult();
            fakeStatus.done = true;
            fakeStatus.success = true;
            fakeStatus.status = 'Succeeded';
            fakeStatus.message = 'Deployment completed.';
            return fakeStatus;
        }

        DeployStatusResult response = new DeployStatusResult();
        response.done = true;
        response.success = true;
        response.status = 'Queued';
        response.message = 'Deployment request accepted. Refresh list in a few seconds to confirm new values.';
        return response;
    }

    private static ManagerEditorOptions buildEditorOptions(List<Target_UI_Controller__mdt> records) {
        Set<String> sectors = new Set<String>();
        Set<String> sectionNames = new Set<String>();
        Set<String> categories = new Set<String>();
        Set<String> sourceSections = new Set<String>();
        Set<String> classifications = new Set<String>();
        Set<String> sourceTypes = new Set<String>{ 'Parameter', 'Driver', 'Derived' };
        Set<String> lineTypes = new Set<String>{ 'Input', 'Formula' };
        Set<String> valueTypes = new Set<String>{ 'number', 'decimal', 'percent' };

        for (Target_UI_Controller__mdt record : records) {
            addIfPresent(sectors, record.Sector__c);
            addIfPresent(sectionNames, record.Section_Name__c);
            addIfPresent(categories, record.Category__c);
            addIfPresent(sourceSections, record.Source_Section__c);
            addIfPresent(classifications, normalizeClassification(record.Classification__c));
            addIfPresent(sourceTypes, record.Source_Type__c);
            addIfPresent(lineTypes, record.UI_Line_Type__c);
            addIfPresent(valueTypes, record.Value_Type__c);
        }

        ManagerEditorOptions options = new ManagerEditorOptions();
        options.sectorOptions = new List<OptionItem>{
            optionItem('All Sectors', ALL_SECTORS_VALUE)
        };
        options.sectorOptions.addAll(toSortedOptions(sectors));
        options.sectionNameOptions = toSortedOptions(sectionNames);
        options.categoryOptions = toSortedOptions(categories);
        options.sourceSectionOptions = toSortedOptions(sourceSections);
        options.classificationOptions = toSortedOptions(classifications);
        options.sourceTypeOptions = toSortedOptions(sourceTypes);
        options.lineTypeOptions = toSortedOptions(lineTypes);
        options.valueTypeOptions = toSortedOptions(valueTypes);
        return options;
    }

    private static TargetUiRow toRow(Target_UI_Controller__mdt record) {
        TargetUiRow row = new TargetUiRow();
        row.developerName = record.DeveloperName;
        row.masterLabel = record.MasterLabel;
        row.sector = record.Sector__c;
        row.sectionName = record.Section_Name__c;
        row.sectionSequence = record.Section_Sequence__c;
        row.category = record.Category__c;
        row.sourceSection = record.Source_Section__c;
        row.parameterDriver = record.Parameter_Driver__c;
        row.sourceValue = record.Source_Value__c;
        row.classification = normalizeClassification(record.Classification__c);
        row.sourceType = record.Source_Type__c;
        row.uiLineType = record.UI_Line_Type__c;
        row.uiSequence = record.UI_Sequence__c;
        row.internalKey = record.Internal_Key__c;
        row.valueType = record.Value_Type__c;
        row.isEditable = record.Is_Editable__c;
        row.isActive = record.Is_Active__c;
        row.fillForwardOnEdit = record.Fill_Forward_On_Edit__c;
        row.formulaKey = record.Formula_Key__c;
        row.formulaTooltip = record.Formula_Tooltip__c;
        row.orderLabel = resolveCategoryDisplayName(record.Category__c, record.Section_Name__c) +
            ' / ' + String.valueOf(record.UI_Sequence__c);
        return row;
    }

    private static void validateRequest(UpsertRecordRequest requestPayload) {
        if (requestPayload == null) {
            throw new AuraHandledException('Provide a record payload.');
        }

        List<String> missingFields = new List<String>();
        if (String.isBlank(requestPayload.sector)) missingFields.add('Sector');
        if (String.isBlank(requestPayload.category) && String.isBlank(requestPayload.sectionName)) missingFields.add('Category');
        if (String.isBlank(requestPayload.parameterDriver)) missingFields.add('Parameter / Driver Label');
        if (String.isBlank(requestPayload.sourceType)) missingFields.add('Source Type');
        if (String.isBlank(requestPayload.uiLineType)) missingFields.add('UI Line Type');
        if (requestPayload.uiSequence == null) missingFields.add('UI Sequence');
        if (String.isBlank(requestPayload.internalKey)) missingFields.add('Internal Key');
        if (String.isBlank(requestPayload.valueType)) missingFields.add('Value Type');

        if (!missingFields.isEmpty()) {
            throw new AuraHandledException('Missing required fields: ' + String.join(missingFields, ', '));
        }
    }

    private static List<Metadata.CustomMetadataValue> buildMetadataValues(UpsertRecordRequest requestPayload) {
        List<Metadata.CustomMetadataValue> values = new List<Metadata.CustomMetadataValue>();
        String resolvedCategory = resolveCategoryDisplayName(requestPayload.category, requestPayload.sectionName);
        String resolvedSectionName = resolveSectionName(requestPayload, resolvedCategory);
        Decimal resolvedSectionSequence = resolveSectionSequence(requestPayload, resolvedCategory);
        values.add(buildStringValue('Sector__c', requestPayload.sector));
        values.add(buildStringValue('Section_Name__c', resolvedSectionName));
        values.add(buildDecimalValue('Section_Sequence__c', resolvedSectionSequence));
        values.add(buildStringValue('Category__c', resolvedCategory));
        values.add(buildStringValue('Source_Section__c', requestPayload.sourceSection));
        values.add(buildStringValue('Parameter_Driver__c', requestPayload.parameterDriver));
        values.add(buildStringValue('Source_Value__c', requestPayload.sourceValue));
        values.add(buildStringValue('Classification__c', normalizeClassification(requestPayload.classification)));
        values.add(buildStringValue('Source_Type__c', requestPayload.sourceType));
        values.add(buildStringValue('UI_Line_Type__c', requestPayload.uiLineType));
        values.add(buildDecimalValue('UI_Sequence__c', requestPayload.uiSequence));
        values.add(buildStringValue('Internal_Key__c', requestPayload.internalKey));
        values.add(buildStringValue('Value_Type__c', requestPayload.valueType));
        values.add(buildBooleanValue('Is_Editable__c', requestPayload.isEditable));
        values.add(buildBooleanValue('Is_Active__c', requestPayload.isActive));
        values.add(buildBooleanValue('Fill_Forward_On_Edit__c', requestPayload.fillForwardOnEdit));
        values.add(buildStringValue('Formula_Key__c', requestPayload.formulaKey));
        values.add(buildStringValue('Formula_Tooltip__c', requestPayload.formulaTooltip));
        return values;
    }

    private static Metadata.CustomMetadataValue buildStringValue(String fieldName, String value) {
        Metadata.CustomMetadataValue metadataValue = new Metadata.CustomMetadataValue();
        metadataValue.field = fieldName;
        metadataValue.value = value == null ? '' : value;
        return metadataValue;
    }

    private static Metadata.CustomMetadataValue buildDecimalValue(String fieldName, Decimal value) {
        Metadata.CustomMetadataValue metadataValue = new Metadata.CustomMetadataValue();
        metadataValue.field = fieldName;
        metadataValue.value = value == null ? 0 : value;
        return metadataValue;
    }

    private static Metadata.CustomMetadataValue buildBooleanValue(String fieldName, Boolean value) {
        Metadata.CustomMetadataValue metadataValue = new Metadata.CustomMetadataValue();
        metadataValue.field = fieldName;
        metadataValue.value = value == true;
        return metadataValue;
    }

    private static String buildManagerSortKey(TargetUiRow row) {
        return String.join(new List<String>{
            normalizeSortValue(row.sector),
            zeroPadInteger(getCategoryDisplaySequence(row.category)),
            zeroPadInteger(row.uiSequence == null ? null : Integer.valueOf(row.uiSequence)),
            normalizeSortValue(row.masterLabel),
            normalizeSortValue(row.developerName)
        }, '|');
    }

    private static String buildDefaultLabel(UpsertRecordRequest requestPayload) {
        List<String> pieces = new List<String>();
        addLabelPiece(pieces, requestPayload.sector);
        addLabelPiece(pieces, requestPayload.internalKey);
        addLabelPiece(pieces, normalizeClassification(requestPayload.classification));
        return String.join(pieces, ' ').trim();
    }

    private static void addLabelPiece(List<String> target, String value) {
        if (!String.isBlank(value)) {
            target.add(value.trim());
        }
    }

    private static String generateDeveloperName(UpsertRecordRequest requestPayload) {
        String sectorPrefix = String.isBlank(requestPayload.sector)
            ? 'Cfg'
            : requestPayload.sector.trim().substring(0, Math.min(3, requestPayload.sector.trim().length()));
        String baseName = sectorPrefix + '_' + requestPayload.internalKey + '_' + normalizeClassification(requestPayload.classification);
        String sanitized = sanitizeDeveloperName(baseName);
        String suffix = String.valueOf(DateTime.now().getTime()).right(6);
        Integer maxBaseLength = 40 - suffix.length();
        if (sanitized.length() > maxBaseLength) {
            sanitized = sanitized.substring(0, maxBaseLength);
        }
        return sanitized + suffix;
    }

    private static String sanitizeDeveloperName(String rawName) {
        String value = String.isBlank(rawName) ? '' : rawName.trim().replaceAll('[^A-Za-z0-9_]', '_');
        if (String.isBlank(value)) {
            return null;
        }
        if (Pattern.matches('^[0-9].*', value)) {
            value = 'R_' + value;
        }
        if (value.length() > 40) {
            value = value.substring(0, 40);
        }
        return value;
    }

    private static String resolveCategoryDisplayName(String categoryName, String sectionName) {
        String normalizedCategory = String.valueOf(categoryName).trim().toLowerCase();
        if (normalizedCategory.contains('op plan')) {
            return 'Op Plan';
        }
        if (normalizedCategory.contains('headcount')) {
            return 'Headcount';
        }
        if (normalizedCategory.contains('hour')) {
            return 'Hours';
        }

        String normalizedSection = String.valueOf(sectionName).trim().toLowerCase();
        if (normalizedSection.contains('non-driver') || normalizedSection.contains('op plan')) {
            return 'Op Plan';
        }
        if (normalizedSection.contains('driver') || normalizedSection.contains('headcount')) {
            return 'Headcount';
        }
        if (normalizedSection.contains('hour')) {
            return 'Hours';
        }
        return String.isBlank(categoryName) ? sectionName : categoryName;
    }

    private static String resolveSectionName(UpsertRecordRequest requestPayload, String resolvedCategory) {
        if (!String.isBlank(requestPayload.sectionName)) {
            return requestPayload.sectionName.trim();
        }
        if (resolvedCategory == 'Op Plan') {
            return '1. Non-Driver Input Information';
        }
        if (resolvedCategory == 'Headcount') {
            return '2. Driver and Headcount Information';
        }
        if (resolvedCategory == 'Hours') {
            return '3. Hour Calculations';
        }
        return resolvedCategory;
    }

    private static Decimal resolveSectionSequence(UpsertRecordRequest requestPayload, String resolvedCategory) {
        if (requestPayload.sectionSequence != null) {
            return requestPayload.sectionSequence;
        }
        return Decimal.valueOf(getCategoryDisplaySequence(resolvedCategory));
    }

    private static Integer getCategoryDisplaySequence(String categoryName) {
        String normalizedCategory = String.valueOf(categoryName).trim().toLowerCase();
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

    private static String zeroPadInteger(Integer value) {
        if (value == null) {
            return '9999';
        }
        String stringValue = String.valueOf(value);
        while (stringValue.length() < 4) {
            stringValue = '0' + stringValue;
        }
        return stringValue;
    }

    private static String normalizeSortValue(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static Boolean matchesSector(Target_UI_Controller__mdt record, String normalizedSector) {
        if (String.isBlank(normalizedSector)) {
            return true;
        }
        return String.valueOf(record.Sector__c).trim().toLowerCase() == normalizedSector;
    }

    private static Boolean matchesSearch(Target_UI_Controller__mdt record, String normalizedSearch) {
        if (String.isBlank(normalizedSearch)) {
            return true;
        }
        return containsIgnoreCase(record.MasterLabel, normalizedSearch) ||
            containsIgnoreCase(record.DeveloperName, normalizedSearch) ||
            containsIgnoreCase(record.Section_Name__c, normalizedSearch) ||
            containsIgnoreCase(record.Parameter_Driver__c, normalizedSearch) ||
            containsIgnoreCase(record.Source_Value__c, normalizedSearch) ||
            containsIgnoreCase(record.Internal_Key__c, normalizedSearch) ||
            containsIgnoreCase(record.Formula_Key__c, normalizedSearch) ||
            containsIgnoreCase(record.Classification__c, normalizedSearch);
    }

    private static Boolean containsIgnoreCase(String candidate, String normalizedNeedle) {
        return !String.isBlank(candidate) && candidate.toLowerCase().contains(normalizedNeedle);
    }

    private static String normalizeSectorFilter(String sectorFilter) {
        if (String.isBlank(sectorFilter) || sectorFilter == ALL_SECTORS_VALUE) {
            return null;
        }
        return sectorFilter.trim().toLowerCase();
    }

    private static String normalizeSearch(String searchTerm) {
        return String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
    }

    private static String normalizeClassification(String classification) {
        if (String.isBlank(classification)) {
            return '';
        }
        String value = classification.trim();
        String lower = value.toLowerCase();
        if (lower == 'shared' || lower == 'mschedule' || lower == 'calculated') {
            return 'Shared';
        }
        if (lower == 'salary' || lower == 'salaried') {
            return 'Salaried';
        }
        if (lower == 'ots') {
            return 'OTS';
        }
        if (lower == 'skilled') {
            return 'Skilled';
        }
        if (lower == 'total') {
            return 'Total';
        }
        return value;
    }

    private static void addIfPresent(Set<String> targetSet, String value) {
        if (!String.isBlank(value)) {
            targetSet.add(value.trim());
        }
    }

    private static List<OptionItem> toSortedOptions(Set<String> values) {
        List<String> sortedValues = new List<String>();
        if (values != null) {
            sortedValues.addAll(values);
        }
        sortedValues.sort();

        List<OptionItem> options = new List<OptionItem>();
        for (String value : sortedValues) {
            options.add(optionItem(value, value));
        }
        return options;
    }

    private static OptionItem optionItem(String label, String value) {
        OptionItem option = new OptionItem();
        option.label = label;
        option.value = value;
        return option;
    }

    public class TargetUiControllerDeployCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            // No-op callback: deployment status is queried by the component.
        }
    }

    public class ManagerDataResponse {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer filteredCount;
        @AuraEnabled public List<TargetUiRow> rows;
        @AuraEnabled public ManagerEditorOptions editorOptions;
    }

    public class ManagerEditorOptions {
        @AuraEnabled public List<OptionItem> sectorOptions;
        @AuraEnabled public List<OptionItem> sectionNameOptions;
        @AuraEnabled public List<OptionItem> categoryOptions;
        @AuraEnabled public List<OptionItem> sourceSectionOptions;
        @AuraEnabled public List<OptionItem> classificationOptions;
        @AuraEnabled public List<OptionItem> sourceTypeOptions;
        @AuraEnabled public List<OptionItem> lineTypeOptions;
        @AuraEnabled public List<OptionItem> valueTypeOptions;
    }

    public class TargetUiRow {
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public String orderLabel;
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public String sector;
        @AuraEnabled public String sectionName;
        @AuraEnabled public Decimal sectionSequence;
        @AuraEnabled public String category;
        @AuraEnabled public String sourceSection;
        @AuraEnabled public String parameterDriver;
        @AuraEnabled public String sourceValue;
        @AuraEnabled public String classification;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String uiLineType;
        @AuraEnabled public Decimal uiSequence;
        @AuraEnabled public String internalKey;
        @AuraEnabled public String valueType;
        @AuraEnabled public Boolean isEditable;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean fillForwardOnEdit;
        @AuraEnabled public String formulaKey;
        @AuraEnabled public String formulaTooltip;
    }

    public class UpsertRecordRequest {
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public String sector;
        @AuraEnabled public String sectionName;
        @AuraEnabled public Decimal sectionSequence;
        @AuraEnabled public String category;
        @AuraEnabled public String sourceSection;
        @AuraEnabled public String parameterDriver;
        @AuraEnabled public String sourceValue;
        @AuraEnabled public String classification;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String uiLineType;
        @AuraEnabled public Decimal uiSequence;
        @AuraEnabled public String internalKey;
        @AuraEnabled public String valueType;
        @AuraEnabled public Boolean isEditable;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean fillForwardOnEdit;
        @AuraEnabled public String formulaKey;
        @AuraEnabled public String formulaTooltip;
    }

    public class DeployRequestResult {
        @AuraEnabled public String deploymentId;
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public Integer recordCount;
        @AuraEnabled public Boolean queued;
        @AuraEnabled public String message;
    }

    public class DeployStatusResult {
        @AuraEnabled public Boolean done;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    public class OptionItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }
}