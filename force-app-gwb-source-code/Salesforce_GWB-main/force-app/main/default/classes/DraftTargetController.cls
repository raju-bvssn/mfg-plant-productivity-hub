/**
 * @description Provides row data and async enqueue actions for the Draft Target table.
 */
public with sharing class DraftTargetController {
    private static final String TARGET_RECORD_TYPE = 'Target';
    private static final String BUDGET_RECORD_TYPE = 'Budget';
    private static final String DRAFT_STATUS = 'Draft';
    private static final String PUBLISHED_STATUS = 'Published';
    private static final String LOCKED_STATUS = 'Locked';
    private static final String PLANT_REVIEW_STATUS = 'Plant Review';
    private static final String PLANT_REVIEW_COMPLETE_STATUS = 'Plant Review Complete';
    private static final String FINANCE_APPROVED_STATUS = 'Finance Approved';
    private static final String PLANT_ADMIN_PERMISSION = 'Plant_Admin';
    private static final String INDUSTRIAL_ENGINEER_PERMISSION = 'Industrial_Engineer';
    private static final String PLANT_VIEWER_PERMISSION = 'Plant_Viewer_ReadOnly';
    private static final String SCHEDULED_VOLUME_PARAMETER = 'Scheduled Volume';
    private static final String TARGET_GENERATION_RECORD = 'Target';
    private static final String BASE_HEADCOUNT_PARAMETER = 'Base Headcount';
    private static final String APPROVED_TARGET_PARAMETER = 'Previous YE Approved Target Changes';
    private static final String LEGACY_APPROVED_TARGET_PARAMETER = 'Approved Target';
    private static final String LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER = 'Advanced Target Changes';
    private static final String TOTAL_MANPOWER_PARAMETER = 'Total Manpower';
    private static final String TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER = 'Total Manpower (Include Target Changes)';
    private static final Set<String> PLANT_SCOPED_VISIBLE_STATUSES = new Set<String>{
        PLANT_REVIEW_STATUS,
        PLANT_REVIEW_COMPLETE_STATUS,
        PUBLISHED_STATUS,
        LOCKED_STATUS
    };
    private static final List<String> MANPOWER_CLASSIFICATIONS = new List<String>{ 'OTS', 'Skilled', 'Salaried' };
    private static final List<String> MONTH_NUMBER_FIELDS = new List<String>{
        'Jan_Number__c', 'Feb_Number__c', 'Mar_Number__c', 'Apr_Number__c', 'May_Number__c', 'Jun_Number__c',
        'Jul_Number__c', 'Aug_Number__c', 'Sep_Number__c', 'Oct_Number__c', 'Nov_Number__c', 'Dec_Number__c'
    };
    private static final List<String> MONTH_DECIMAL_FIELDS = new List<String>{
        'Jan_Decimal__c', 'Feb_Decimal__c', 'Mar_Decimal__c', 'Apr_Decimal__c', 'May_Decimal__c', 'Jun_Decimal__c',
        'Jul_Decimal__c', 'Aug_Decimal__c', 'Sep_Decimal__c', 'Oct_Decimal__c', 'Nov_Decimal__c', 'Dec_Decimal__c'
    };
    private static final List<String> MONTH_PERCENT_FIELDS = new List<String>{
        'Jan_Percent__c', 'Feb_Percent__c', 'Mar_Percent__c', 'Apr_Percent__c', 'May_Percent__c', 'Jun_Percent__c',
        'Jul_Percent__c', 'Aug_Percent__c', 'Sep_Percent__c', 'Oct_Percent__c', 'Nov_Percent__c', 'Dec_Percent__c'
    };
    private static final Set<String> TOTAL_MANPOWER_DRIVER_NAMES = new Set<String>{
        'Productivity', 'ARC', 'LMS', 'Vacation Replacement', 'Op Plan', 'Content',
        'Sourcing', 'Mfg Opt', 'Launch', 'Containment', 'Other/Excess'
    };
    @TestVisible private static String currentUserPersonaOverride;

    public class TargetRow {
        @AuraEnabled public Id targetId;
        @AuraEnabled public String targetName;
        @AuraEnabled public String targetVersion;
        @AuraEnabled public String targetStatus;
        @AuraEnabled public String targetYear;
        @AuraEnabled public String targetCreatedOn;
    }

    public class DraftTargetRow {
        @AuraEnabled public Id plantSectorId;
        @AuraEnabled public Id plantId;
        @AuraEnabled public Id plantProgramId;
        @AuraEnabled public String region;
        @AuraEnabled public String plantName;
        @AuraEnabled public String programCode;
        @AuraEnabled public String lineNumber;
        @AuraEnabled public String partType;
        @AuraEnabled public String functionalArea;
        @AuraEnabled public String sector;
        @AuraEnabled public Boolean checkboxDisabled;
        @AuraEnabled public List<TargetRow> targets;
    }

    public class EnqueueDraftTargetResult {
        @AuraEnabled public Id jobId;
        @AuraEnabled public Integer submittedCount;
    }

    public class EnqueueCloneTargetResult {
        @AuraEnabled public Id jobId;
        @AuraEnabled public Integer submittedCount;
        @AuraEnabled public List<String> skippedTargetNames;
    }

    public class TargetYearContext {
        @AuraEnabled public String targetYear;
        @AuraEnabled public Boolean isNewWindowOpen;
        @AuraEnabled public Boolean isSystemAdmin;
        @AuraEnabled public Boolean isHiddenWindow;
        @AuraEnabled public Boolean isPlantScopedUser;
        @AuraEnabled public Boolean isPlantAdminLikeUser;
        @AuraEnabled public Boolean isIndustrialEngineerUser;
        @AuraEnabled public Boolean isPlantViewerUser;
    }

    public class CloneDraftTargetResult {
        @AuraEnabled public Integer submittedCount;
        @AuraEnabled public List<Id> clonedTargetIds;
    }

    private class CloneConfigAllowlist {
        Set<String> parameterKeys = new Set<String>();
        Set<String> driverKeys = new Set<String>();
        Boolean hasConfig = false;
    }

    public class PlantOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
        @AuraEnabled public String region;
        @AuraEnabled public String sector;

        public PlantOption() {}

        public PlantOption(Plant__c plantRecord) {
            value = plantRecord.Id;
            label = plantRecord.Name;
            region = plantRecord.Auth_Region__c == null ? '' : String.valueOf(plantRecord.Auth_Region__c);
            sector = plantRecord.Auth_Sector__c == null ? '' : String.valueOf(plantRecord.Auth_Sector__c);
        }
    }

    public class DeleteDraftBudgetResult {
        @AuraEnabled public Id deletedDraftBudgetId;
        @AuraEnabled public String deletedDraftBudgetName;
    }

    public class DeleteTargetResult {
        @AuraEnabled public Id deletedTargetId;
        @AuraEnabled public String deletedTargetName;
    }

    public class UpdateStatusResult {
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public List<String> skippedTargetNames;
    }

    public class PublishResult {
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer skippedCount;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class PlantProgramOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String programCode;

        public PlantProgramOption(String label, String value, String programCode) {
            this.label = label;
            this.value = value;
            this.programCode = programCode;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DraftTargetRow> getPlantSectorRows() {
        String nextCalendarYear = computeTargetYear(loadTargetGenerationConfig());
        Boolean restrictToPlantScopedStatuses = isPlantScopedTargetUser();

        List<Plant_Sector__c> plantSectors = [
            SELECT Id, Plant__c, Plant__r.Name, Plant__r.Auth_Sector__c, Plant_Program__c, Region__c, Program_Code__c, Line_Number__c,
                   Part_Type__c, Functional_Area__c, Auth_Sector__c, Active__c, Product_Type__c
            FROM Plant_Sector__c WHERE Active__c = true
            ORDER BY Region__c, Plant__r.Name, Auth_Sector__c
        ];

        Set<Id> plantIds = new Set<Id>();
        Set<String> sectors = new Set<String>();
        Set<Id> plantSectorIds = new Set<Id>();

        for (Plant_Sector__c plantSector : plantSectors) {
            plantSectorIds.add(plantSector.Id);
            if (plantSector.Plant__c != null) {
                plantIds.add(plantSector.Plant__c);
            }
            if (String.isNotBlank(plantSector.Auth_Sector__c)) {
                sectors.add(plantSector.Auth_Sector__c);
            }
        }

        Map<Id, List<TargetRow>> targetsByPlantSector = new Map<Id, List<TargetRow>>();
        Map<String, List<TargetRow>> targetsByPlantSectorKey = new Map<String, List<TargetRow>>();

        if (!plantSectorIds.isEmpty() || (!plantIds.isEmpty() && !sectors.isEmpty())) {
            for (GWB_Year__c targetRecord : [
                SELECT Id, Name, Plant_Sector__c, Plant__c, Sector__c, Target_Name__c, M_Schedule_Version__c,
                       Status__c, Year__c, CreatedDate, RecordType.DeveloperName
                FROM GWB_Year__c
                WHERE RecordType.DeveloperName = :TARGET_RECORD_TYPE
                AND Year__c = :nextCalendarYear
                AND (
                    Plant_Sector__c IN :plantSectorIds
                    OR (Plant__c IN :plantIds AND Sector__c IN :sectors)
                )
                ORDER BY Year__c DESC, CreatedDate DESC
            ]) {
                if (restrictToPlantScopedStatuses && !PLANT_SCOPED_VISIBLE_STATUSES.contains(targetRecord.Status__c)) {
                    continue;
                }
                String fallbackKey = buildPlantSectorKey(targetRecord.Plant__c, targetRecord.Sector__c);
                TargetRow targetRow = new TargetRow();
                targetRow.targetId = targetRecord.Id;
                String normalizedVersion = normalizeVersion(targetRecord.M_Schedule_Version__c);
                targetRow.targetName = buildTargetDisplayName(targetRecord.Year__c, normalizedVersion, targetRecord.Name);
                targetRow.targetVersion = normalizedVersion;
                targetRow.targetStatus = targetRecord.Status__c;
                targetRow.targetYear = targetRecord.Year__c;
                targetRow.targetCreatedOn = targetRecord.CreatedDate != null ? String.valueOf(targetRecord.CreatedDate) : '';

                if (targetRecord.Plant_Sector__c != null) {
                    if (!targetsByPlantSector.containsKey(targetRecord.Plant_Sector__c)) {
                        targetsByPlantSector.put(targetRecord.Plant_Sector__c, new List<TargetRow>());
                    }
                    targetsByPlantSector.get(targetRecord.Plant_Sector__c).add(targetRow);
                }

                if (targetRecord.Plant_Sector__c == null) {
                    if (!targetsByPlantSectorKey.containsKey(fallbackKey)) {
                        targetsByPlantSectorKey.put(fallbackKey, new List<TargetRow>());
                    }
                    targetsByPlantSectorKey.get(fallbackKey).add(targetRow);
                }
            }
        }

        List<DraftTargetRow> rows = new List<DraftTargetRow>();
        for (Plant_Sector__c plantSector : plantSectors) {
            List<TargetRow> matchingTargets = targetsByPlantSector.get(plantSector.Id);
            if (matchingTargets == null) {
                matchingTargets = targetsByPlantSectorKey.get(buildPlantSectorKey(plantSector.Plant__c, plantSector.Auth_Sector__c));
            }

            DraftTargetRow row = new DraftTargetRow();
            row.plantSectorId = plantSector.Id;
            row.plantId = plantSector.Plant__c;
            row.plantProgramId = plantSector.Plant_Program__c;
            row.region = plantSector.Region__c;
            row.plantName = plantSector.Plant__r != null ? plantSector.Plant__r.Name : '';
            row.programCode = plantSector.Program_Code__c;
            row.lineNumber = plantSector.Line_Number__c;
            row.partType = plantSector.Part_Type__c;
            row.functionalArea = plantSector.Functional_Area__c;
            row.sector = plantSector.Auth_Sector__c;
            row.checkboxDisabled = false;
            row.targets = matchingTargets != null ? matchingTargets : new List<TargetRow>();
            rows.add(row);
        }

        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTargetStatusOrder() {
        List<String> statusOrder = new List<String>();
        for (Schema.PicklistEntry entry : GWB_Year__c.Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                statusOrder.add(entry.getValue());
            }
        }
        return statusOrder;
    }

    @AuraEnabled
    public static TargetYearContext getTargetYearContext() {
        Target_Generation__mdt config = loadTargetGenerationConfig();
        TargetYearContext ctx = new TargetYearContext();
        ctx.targetYear = computeTargetYear(config);
        ctx.isNewWindowOpen = isNewTargetWindowOpen(config);
        ctx.isSystemAdmin = hasCustomPermission('GWB_System_Admin');
        // Admin bypass: if user is a system admin, the exclude window does not hide the component
        ctx.isHiddenWindow = !ctx.isSystemAdmin && isInExcludeWindow(config);
        ctx.isPlantAdminLikeUser = isPlantAdminLikeUser();
        ctx.isIndustrialEngineerUser = isIndustrialEngineerUser();
        ctx.isPlantViewerUser = isPlantViewerUser();
        ctx.isPlantScopedUser = isPlantScopedTargetUser();
        return ctx;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getMScheduleOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Plant_Volume__c.Data_Point_Value__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PlantOption> getPlantOptions() {
        List<PlantOption> options = new List<PlantOption>();
        for (Plant__c plantRecord : [
            SELECT Id, Name, Auth_Region__c, Auth_Sector__c
            FROM Plant__c
            ORDER BY Name
        ]) {
            options.add(new PlantOption(plantRecord));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPlantSectorOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Plant__c.Auth_Sector__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getProgramCodeOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Plant_Sector__c.Program_Code__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFunctionalAreaOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Plant_Sector__c.Functional_Area__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PlantProgramOption> getPlantProgramOptions(Id plantId) {
        if (plantId == null) {
            return new List<PlantProgramOption>();
        }

        List<Plant_Program__c> plantPrograms = [
            SELECT Id, Name, Program_Code__c, Plant_Program_Name__c, Include__c, Shop__c
            FROM Plant_Program__c
            WHERE Auth_Plant_Name__c = :plantId
            AND Program_Code__c != null
            ORDER BY Plant_Program_Name__c, Program_Code__c, Name
        ];

        List<Plant_Program__c> filteredPlantPrograms = new List<Plant_Program__c>();
        for (Plant_Program__c plantProgram : plantPrograms) {
            if (plantProgram.Include__c != true) {
                continue;
            }
            if (String.isBlank(plantProgram.Shop__c) || plantProgram.Shop__c.contains('All')) {
                continue;
            }
            filteredPlantPrograms.add(plantProgram);
        }

        Map<String, Integer> countsByProgramName = new Map<String, Integer>();
        for (Plant_Program__c plantProgram : filteredPlantPrograms) {
            String programName = String.isNotBlank(plantProgram.Plant_Program_Name__c)
                ? plantProgram.Plant_Program_Name__c
                : plantProgram.Program_Code__c;
            countsByProgramName.put(
                programName,
                countsByProgramName.containsKey(programName) ? countsByProgramName.get(programName) + 1 : 1
            );
        }

        List<PlantProgramOption> options = new List<PlantProgramOption>();
        for (Plant_Program__c plantProgram : filteredPlantPrograms) {
            String programCode = plantProgram.Program_Code__c;
            String programName = String.isNotBlank(plantProgram.Plant_Program_Name__c)
                ? plantProgram.Plant_Program_Name__c
                : programCode;
            String label = countsByProgramName.get(programName) > 1
                ? programName + ' (' + plantProgram.Shop__c + ')'
                : programName;
            options.add(new PlantProgramOption(label, String.valueOf(plantProgram.Id), programCode));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPartTypeOptions(Id plantId) {
        if (plantId == null) {
            return new List<PicklistOption>();
        }

        Set<String> uniquePartTypes = new Set<String>();
        for (Program_Master__c programMaster : [
            SELECT Part_Type__c
            FROM Program_Master__c
            WHERE Plant_Name__c = :plantId
            AND RecordType.DeveloperName = 'Part_Type'
            AND Part_Type__c != null
            ORDER BY Part_Type__c
        ]) {
            uniquePartTypes.add(programMaster.Part_Type__c);
        }

        List<String> sortedPartTypes = new List<String>(uniquePartTypes);
        sortedPartTypes.sort();

        List<PicklistOption> options = new List<PicklistOption>();
        for (String partType : sortedPartTypes) {
            options.add(new PicklistOption(partType, partType));
        }
        return options;
    }

    @AuraEnabled
    public static DraftTargetRow createPlantSector(
        Id plantId,
        Id plantProgramId,
        String programCode,
        String lineNumber,
        String partType,
        String functionalArea
    ) {
        if (plantId == null) {
            throw new AuraHandledException('Plant is required to add a new Plant Sector row.');
        }

        Plant__c selectedPlant = [
            SELECT Id, Name
            FROM Plant__c
            WHERE Id = :plantId
            LIMIT 1
        ];

        if (hasExistingPlantSector(plantId)) {
            throw new AuraHandledException(
                'A Plant Sector record already exists for plant "' + selectedPlant.Name + '".'
            );
        }

        Plant_Sector__c plantSector = new Plant_Sector__c(
            Plant__c = plantId,
            Plant_Program__c = plantProgramId,
            Program_Code__c = programCode,
            Line_Number__c = lineNumber,
            Part_Type__c = partType,
            Functional_Area__c = functionalArea,
            Active__c = true
        );
        insert plantSector;

        Plant_Sector__c createdRow = [
            SELECT Id, Plant__c, Plant__r.Name, Plant__r.Auth_Sector__c, Plant_Program__c, Region__c, Program_Code__c, Line_Number__c,
                   Part_Type__c, Functional_Area__c, Auth_Sector__c
            FROM Plant_Sector__c
            WHERE Id = :plantSector.Id
            LIMIT 1
        ];

        DraftTargetRow row = new DraftTargetRow();
        row.plantSectorId = createdRow.Id;
        row.plantId = createdRow.Plant__c;
        row.plantProgramId = createdRow.Plant_Program__c;
        row.region = createdRow.Region__c;
        row.plantName = createdRow.Plant__r != null ? createdRow.Plant__r.Name : '';
        row.programCode = createdRow.Program_Code__c;
        row.lineNumber = createdRow.Line_Number__c;
        row.partType = createdRow.Part_Type__c;
        row.functionalArea = createdRow.Functional_Area__c;
        row.sector = createdRow.Auth_Sector__c;
        row.checkboxDisabled = false;
        row.targets = new List<TargetRow>();
        return row;
    }

    private static Boolean hasExistingPlantSector(Id plantId) {
        return [
            SELECT COUNT()
            FROM Plant_Sector__c
            WHERE Plant__c = :plantId
        ] > 0;
    }

    @AuraEnabled
    public static EnqueueDraftTargetResult enqueueDraftTargets(List<Id> plantSectorIds, String versionValue) {
        if (plantSectorIds == null || plantSectorIds.isEmpty()) {
            throw new AuraHandledException('Select at least one Plant Sector row before creating target records.');
        }
        if (String.isBlank(versionValue)) {
            throw new AuraHandledException('Select an M-Schedule Data Point value.');
        }

        Set<Id> uniquePlantSectorIds = new Set<Id>(plantSectorIds);
        Id initiatedByUserId = (Id)UserInfo.getUserId();
        Id jobId = Database.executeBatch(
            new DraftTargetCreationBatch(
                new List<Id>(uniquePlantSectorIds),
                normalizeVersion(versionValue),
                initiatedByUserId
            ),
            20
        );

        EnqueueDraftTargetResult result = new EnqueueDraftTargetResult();
        result.jobId = jobId;
        result.submittedCount = uniquePlantSectorIds.size();
        return result;
    }

    @AuraEnabled
    public static CloneDraftTargetResult cloneDraftTargets(List<Id> targetIds, String versionValue) {
        enforceCloneAccess();
        return cloneDraftTargetsNow(targetIds, versionValue);
    }

    @AuraEnabled
    public static EnqueueCloneTargetResult enqueueCloneDraftTargets(List<Id> targetIds, String versionValue) {
        enforceCloneAccess();
        if (targetIds == null || targetIds.isEmpty()) {
            throw new AuraHandledException('Select at least one target before cloning.');
        }
        if (String.isBlank(versionValue)) {
            throw new AuraHandledException('Select an M-Schedule Data Point.');
        }

        Set<Id> uniqueTargetIds = new Set<Id>(targetIds);
        String normalizedVersion = normalizeVersion(versionValue);

        // Separate cloneable from Published/Locked
        List<Id> cloneableIds = new List<Id>();
        List<String> skippedTargetNames = new List<String>();
        List<GWB_Year__c> candidates = new List<GWB_Year__c>();
        for (GWB_Year__c t : [
            SELECT Id, Name, Status__c, Plant_Sector__c, Plant_Sector__r.Name
            FROM GWB_Year__c
            WHERE Id IN :uniqueTargetIds
            AND RecordType.DeveloperName = :TARGET_RECORD_TYPE
        ]) {
            if (t.Status__c == PUBLISHED_STATUS || t.Status__c == LOCKED_STATUS) {
                skippedTargetNames.add(t.Name);
            } else {
                //cloneableIds.add(t.Id);
                candidates.add(t);
            }
        }
        
        Set<Id> candidatePlantSectorIds = new Set<Id>();
        for (GWB_Year__c candidate : candidates) {
            if (candidate.Plant_Sector__c != null) {
                candidatePlantSectorIds.add(candidate.Plant_Sector__c);
            }
        }
        
        Set<Id> plantSectorsWithRequestedVersion = new Set<Id>();
        if (!candidatePlantSectorIds.isEmpty()) {
            for (GWB_Year__c existingTarget : [
                SELECT Id, Plant_Sector__c
                FROM GWB_Year__c
                WHERE RecordType.DeveloperName = :TARGET_RECORD_TYPE
                AND Plant_Sector__c IN :candidatePlantSectorIds
                AND M_Schedule_Version__c = :normalizedVersion
                //AND Id NOT IN :uniqueTargetIds
            ]) {
                if (existingTarget.Plant_Sector__c != null) {
                    plantSectorsWithRequestedVersion.add(existingTarget.Plant_Sector__c);
                }
            }
        }
        
        for (GWB_Year__c candidate : candidates) {
            if (candidate.Plant_Sector__c != null && plantSectorsWithRequestedVersion.contains(candidate.Plant_Sector__c)) {
                skippedTargetNames.add(
                    candidate.Plant_Sector__r != null && String.isNotBlank(candidate.Plant_Sector__r.Name)
                        ? candidate.Plant_Sector__r.Name
                        : candidate.Name
                );
            } else {
                cloneableIds.add(candidate.Id);
            }
        }
        
        EnqueueCloneTargetResult result = new EnqueueCloneTargetResult();
        result.skippedTargetNames = skippedTargetNames;

        if (cloneableIds.isEmpty()) {
            //throw new AuraHandledException('All selected targets are ' + PUBLISHED_STATUS + ' or ' + LOCKED_STATUS + ' and cannot be cloned.');
            //throw new AuraHandledException('All selected targets are ineligible for clone because they are ' + PUBLISHED_STATUS + '/' + LOCKED_STATUS + ' or the selected Target Generation Config already has the chosen M-Schedule version.');
            result.jobId = null;
            result.submittedCount = 0;
            return result;
        }

        Id initiatedByUserId = (Id)UserInfo.getUserId();
        Id jobId = Database.executeBatch(
            new DraftTargetCloneBatch(
                cloneableIds,
                //normalizeVersion(versionValue),
                normalizedVersion,
                initiatedByUserId
            ),
            20
        );

        //EnqueueCloneTargetResult result = new EnqueueCloneTargetResult();
        result.jobId = jobId;
        result.submittedCount = cloneableIds.size();
        //result.skippedTargetNames = skippedTargetNames;
        return result;
    }

    private static CloneDraftTargetResult cloneDraftTargetsNow(List<Id> targetIds, String versionValue) {
        if (targetIds == null || targetIds.isEmpty()) {
            throw new AuraHandledException('Select at least one target before cloning.');
        }
        if (String.isBlank(versionValue)) {
            throw new AuraHandledException('Select an M-Schedule Data Point.');
        }

        Set<Id> uniqueTargetIds = new Set<Id>(targetIds);
        String normalizedVersion = normalizeVersion(versionValue);
        List<GWB_Year__c> queriedTargets = [
            SELECT Id, Name, Plant_Sector__c, Plant_Sector__r.Plant_Program__c, Plant__c, Plant__r.Vehicle_Brand__c, Plant_Program__c, Sector__c, Target_Name__c, M_Schedule_Version__c,
                   Status__c, Year__c, Version__c, RecordType.DeveloperName
            FROM GWB_Year__c
            WHERE Id IN :uniqueTargetIds
            AND RecordType.DeveloperName = :TARGET_RECORD_TYPE
        ];
        
        Set<Id> selectedPlantSectorIds = new Set<Id>();
        for (GWB_Year__c t : queriedTargets) {
            if (t.Plant_Sector__c != null) {
                selectedPlantSectorIds.add(t.Plant_Sector__c);
            }
        }
        
        Set<Id> plantSectorsWithRequestedVersion = new Set<Id>();
        if (!selectedPlantSectorIds.isEmpty()) {
            for (GWB_Year__c existingTarget : [
                SELECT Id, Plant_Sector__c
                FROM GWB_Year__c
                WHERE RecordType.DeveloperName = :TARGET_RECORD_TYPE
                AND Plant_Sector__c IN :selectedPlantSectorIds
                AND M_Schedule_Version__c = :normalizedVersion
                //AND Id NOT IN :uniqueTargetIds
            ]) {
                if (existingTarget.Plant_Sector__c != null) {
                    plantSectorsWithRequestedVersion.add(existingTarget.Plant_Sector__c);
                }
            }
        }
        
        List<GWB_Year__c> sourceTargets = new List<GWB_Year__c>();
        for (GWB_Year__c sourceTarget : queriedTargets) {
            if (sourceTarget.Plant_Sector__c != null && plantSectorsWithRequestedVersion.contains(sourceTarget.Plant_Sector__c)) {
                continue;
            }
            sourceTargets.add(sourceTarget);
        }
        
        CloneDraftTargetResult result = new CloneDraftTargetResult();
        result.clonedTargetIds = new List<Id>();

        if (sourceTargets.isEmpty()) {
            //throw new AuraHandledException('No cloneable target records were found.');
            //throw new AuraHandledException('No cloneable target records were found because selected Target Generation Config records already have the chosen M-Schedule version.');
            result.submittedCount = 0;
            return result;
        }

        List<GWB_Year__c> clonedTargets = new List<GWB_Year__c>();
        List<GWB_Month__c> clonedMonths = new List<GWB_Month__c>();
        List<GWB_Month__c> clonedDriverRows = new List<GWB_Month__c>();
        List<GWB_Budget_Comment__c> clonedComments = new List<GWB_Budget_Comment__c>();
        Map<Id, Map<String, Decimal>> scheduledVolumesByTargetId =
            DraftTargetCreationService.loadScheduledVolumeBySourceTarget(sourceTargets, normalizedVersion);
        Map<Id, Decimal> prevYearDecByTargetId =
            DraftTargetCreationService.loadPrevYearScheduledVolumeDecByTarget(sourceTargets);
        Map<Id, CloneConfigAllowlist> cloneAllowlistsByTargetId = buildActiveCloneConfigAllowlists(sourceTargets);

        Map<Id, List<GWB_Month__c>> monthsByTargetId = new Map<Id, List<GWB_Month__c>>();
        for (GWB_Month__c monthRow : [
            SELECT Id, GWB_Year__c, Section__c, Category__c, Value_Type__c, UI_Sequence__c, Avg_Total__c,
                   Driver__c, Classification__c,
                   Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                   Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c,
                   Prev_Dec_Number__c, Prev_Dec_Decimal__c, Prev_Dec_Percent__c, Parameter__c, Average_HC__c,
                   Apr_Number__c, Aug_Number__c, Dec_Number__c, Feb_Number__c, Jan_Number__c, Jul_Number__c, Jun_Number__c,
                   Mar_Number__c, May_Number__c, Nov_Number__c, Oct_Number__c, Sep_Number__c,
                   Annual_TotalDecimal__c, Annual_TotalPercent__c, Annual_TotalNumber__c,
                   Annual_TotalDecimal1__c, Annual_TotalPercent1__c, Annual_TotalNumber1__c,
                   Plant__c, Sector__c, Year__c, Data_Point_Value__c
            FROM GWB_Month__c
            WHERE GWB_Year__c IN :uniqueTargetIds
            AND Parameter__c != null
        ]) {
            if (!shouldCloneParameterRow(monthRow, cloneAllowlistsByTargetId.get(monthRow.GWB_Year__c))) {
                continue;
            }
            if (!monthsByTargetId.containsKey(monthRow.GWB_Year__c)) {
                monthsByTargetId.put(monthRow.GWB_Year__c, new List<GWB_Month__c>());
            }
            monthsByTargetId.get(monthRow.GWB_Year__c).add(monthRow);
        }
        Map<Id, Map<String, GWB_Month__c>> publishedPrevDecRowsByTargetId =
            loadPreviousPublishedRowsBySourceTarget(sourceTargets, monthsByTargetId);

        Map<Id, List<GWB_Budget_Comment__c>> commentsByTargetId = new Map<Id, List<GWB_Budget_Comment__c>>();
        for (GWB_Budget_Comment__c commentRow : [
            SELECT Id, GWB_Year__c, Cell_Key__c, Classification__c, Comment_Text__c,
                   Month_Key__c, Row_Key__c, Row_Label__c, Table_Name__c, Value_Snapshot__c,
                   Original_Created_Date__c, CreatedDate
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c IN :uniqueTargetIds
        ]) {
            if (!commentsByTargetId.containsKey(commentRow.GWB_Year__c)) {
                commentsByTargetId.put(commentRow.GWB_Year__c, new List<GWB_Budget_Comment__c>());
            }
            commentsByTargetId.get(commentRow.GWB_Year__c).add(commentRow);
        }

        Map<Id, List<GWB_Month__c>> driverRowsByTargetId = new Map<Id, List<GWB_Month__c>>();
        for (GWB_Month__c driverRow : [
            SELECT Id, GWB_Year__c, Section__c, Category__c, Value_Type__c, UI_Sequence__c, Avg_Total__c,
                   Driver__c, Classification__c, Plant__c, Sector__c, Year__c, Data_Point_Value__c,
                   Annual_TotalDecimal1__c, Annual_TotalPercent1__c, Annual_TotalNumber1__c,
                   Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c,
                   Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c IN :uniqueTargetIds
            AND Driver__c != null
        ]) {
            if (!shouldCloneDriverRow(driverRow, cloneAllowlistsByTargetId.get(driverRow.GWB_Year__c))) {
                continue;
            }
            if (!driverRowsByTargetId.containsKey(driverRow.GWB_Year__c)) {
                driverRowsByTargetId.put(driverRow.GWB_Year__c, new List<GWB_Month__c>());
            }
            driverRowsByTargetId.get(driverRow.GWB_Year__c).add(driverRow);
        }

        for (GWB_Year__c sourceTarget : sourceTargets) {
            GWB_Year__c clonedTarget = sourceTarget.clone(false, false, false, false);
            clonedTarget.Status__c = DRAFT_STATUS;
            clonedTarget.M_Schedule_Version__c = normalizedVersion;
            clonedTarget.Version__c = buildTargetVersion(sourceTarget.Year__c, normalizedVersion);
            clonedTarget.Plant_Program__c = sourceTarget.Plant_Sector__r == null || sourceTarget.Plant_Sector__r.Plant_Program__c == null
                ? sourceTarget.Plant_Program__c
                : sourceTarget.Plant_Sector__r.Plant_Program__c;
            clonedTargets.add(clonedTarget);
        }

        insert clonedTargets;

        for (Integer index = 0; index < sourceTargets.size(); index++) {
            GWB_Year__c sourceTarget = sourceTargets[index];
            GWB_Year__c clonedTarget = clonedTargets[index];
            List<GWB_Month__c> targetClonedMonths = new List<GWB_Month__c>();
            List<GWB_Month__c> targetClonedDriverRows = new List<GWB_Month__c>();
            List<GWB_Month__c> sourceMonths = monthsByTargetId.get(sourceTarget.Id);
            if (sourceMonths != null) {
                for (GWB_Month__c sourceMonth : sourceMonths) {
                    GWB_Month__c clonedMonth = sourceMonth.clone(false, false, false, false);
                    clonedMonth.GWB_Year__c = clonedTarget.Id;
                    clonedMonth.Parameter__c = normalizeCloneParameterLabel(clonedMonth.Parameter__c);
                    clonedMonth.Plant__c = clonedTarget.Plant__c;
                    clonedMonth.Sector__c = clonedTarget.Sector__c;
                    clonedMonth.Year__c = clonedTarget.Year__c;
                    clonedMonth.Data_Point_Value__c = normalizedVersion;
                    if (sourceMonth.Parameter__c == SCHEDULED_VOLUME_PARAMETER) {
                        applyScheduledVolumeValues(
                            clonedMonth,
                            prevYearDecByTargetId.get(sourceTarget.Id),
                            scheduledVolumesByTargetId.get(sourceTarget.Id)
                        );
                    } else {
                        applyPublishedPrevDecValues(
                            clonedMonth,
                            publishedPrevDecRowsByTargetId.get(sourceTarget.Id),
                            sourceMonth
                        );
                    }
                    if (normalizeCloneParameterLabel(sourceMonth.Parameter__c) == APPROVED_TARGET_PARAMETER) {
                        clearCurrentYearMonthValues(clonedMonth);
                    }
                    targetClonedMonths.add(clonedMonth);
                }
            }

            List<GWB_Month__c> sourceDriverRows = driverRowsByTargetId.get(sourceTarget.Id);
            if (sourceDriverRows != null) {
                for (GWB_Month__c sourceDriverRow : sourceDriverRows) {
                    GWB_Month__c clonedDriverRow = sourceDriverRow.clone(false, false, false, false);
                    clonedDriverRow.GWB_Year__c = clonedTarget.Id;
                    clonedDriverRow.Plant__c = clonedTarget.Plant__c;
                    clonedDriverRow.Sector__c = clonedTarget.Sector__c;
                    clonedDriverRow.Year__c = clonedTarget.Year__c;
                    clonedDriverRow.Data_Point_Value__c = normalizedVersion;
                    targetClonedDriverRows.add(clonedDriverRow);
                }
            }

            syncClonedBaseHeadcountRows(targetClonedMonths, targetClonedDriverRows);
            clonedMonths.addAll(targetClonedMonths);
            clonedDriverRows.addAll(targetClonedDriverRows);

            List<GWB_Budget_Comment__c> sourceComments = commentsByTargetId.get(sourceTarget.Id);
            if (sourceComments != null) {
                for (GWB_Budget_Comment__c sourceComment : sourceComments) {
                    GWB_Budget_Comment__c clonedComment = sourceComment.clone(false, false, false, false);
                    clonedComment.GWB_Year__c = clonedTarget.Id;
                    clonedComment.Original_Created_Date__c = sourceComment.Original_Created_Date__c != null
                        ? sourceComment.Original_Created_Date__c
                        : sourceComment.CreatedDate;
                    clonedComments.add(clonedComment);
                }
            }
        }

        if (!clonedMonths.isEmpty()) {
            insert clonedMonths;
        }
        if (!clonedDriverRows.isEmpty()) {
            insert clonedDriverRows;
        }
        if (!clonedComments.isEmpty()) {
            insert clonedComments;
        }

        //CloneDraftTargetResult result = new CloneDraftTargetResult();
        result.submittedCount = clonedTargets.size();
        //result.clonedTargetIds = new List<Id>();
        for (GWB_Year__c clonedTarget : clonedTargets) {
            result.clonedTargetIds.add(clonedTarget.Id);
        }
        return result;
    }

    private static Map<Id, CloneConfigAllowlist> buildActiveCloneConfigAllowlists(List<GWB_Year__c> sourceTargets) {
        Map<Id, CloneConfigAllowlist> allowlistsByTargetId = new Map<Id, CloneConfigAllowlist>();
        if (sourceTargets == null || sourceTargets.isEmpty()) {
            return allowlistsByTargetId;
        }

        List<Target_UI_Controller__mdt> activeConfigs = [
            SELECT Sector__c, Source_Type__c, UI_Line_Type__c, Parameter_Driver__c, Source_Value__c,
                   Classification__c, Formula_Key__c
            FROM Target_UI_Controller__mdt
            WHERE Is_Active__c = true
        ];

        for (GWB_Year__c sourceTarget : sourceTargets) {
            CloneConfigAllowlist allowlist = new CloneConfigAllowlist();
            Set<String> sectorFilters = buildCloneSectorFilters(sourceTarget.Sector__c);
            for (Target_UI_Controller__mdt config : activeConfigs) {
                if (config == null || !sectorFilters.contains(normalizeCloneText(config.Sector__c))) {
                    continue;
                }
                addCloneConfigKeys(allowlist, config);
            }
            allowlistsByTargetId.put(sourceTarget.Id, allowlist);
        }
        return allowlistsByTargetId;
    }

    private static void addCloneConfigKeys(CloneConfigAllowlist allowlist, Target_UI_Controller__mdt config) {
        if (allowlist == null || config == null) {
            return;
        }

        String sourceType = String.isBlank(config.Source_Type__c) ? '' : config.Source_Type__c.trim();
        Boolean storesAsParameter = sourceType == 'Parameter' || (
            sourceType == 'Derived' &&
            (isCloneFormulaLine(config.UI_Line_Type__c) || isCloneTotalLine(config.UI_Line_Type__c) || String.isNotBlank(config.Formula_Key__c))
        );
        Boolean storesAsDriver = sourceType == 'Driver';
        if (!storesAsParameter && !storesAsDriver) {
            return;
        }

        allowlist.hasConfig = true;
        List<String> labels = buildCloneConfigCandidateLabels(config);
        for (String label : labels) {
            if (storesAsParameter) {
                addCloneLookupKey(allowlist.parameterKeys, label, config.Classification__c);
            }
            if (storesAsDriver) {
                addCloneLookupKey(allowlist.driverKeys, normalizeCloneDriverValue(label), config.Classification__c);
            }
        }
    }

    private static List<String> buildCloneConfigCandidateLabels(Target_UI_Controller__mdt config) {
        List<String> labels = new List<String>();
        if (config == null) {
            return labels;
        }

        addUniqueCloneLabel(labels, config.Parameter_Driver__c);
        addUniqueCloneLabel(labels, config.Source_Value__c);

        if (containsApprovedTargetFamily(labels)) {
            addApprovedTargetCloneLabels(labels);
        }

        if (config.Formula_Key__c == 'totalManpower') {
            addUniqueCloneLabel(labels, TOTAL_MANPOWER_PARAMETER);
            addUniqueCloneLabel(labels, TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER);
        }

        return labels;
    }

    private static void addUniqueCloneLabel(List<String> labels, String label) {
        if (labels == null || String.isBlank(label)) {
            return;
        }
        String trimmedLabel = normalizeCloneParameterLabel(label);
        if (!labels.contains(trimmedLabel)) {
            labels.add(trimmedLabel);
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
        String normalized = normalizeCloneText(parameterValue);
        return normalized.contains('approved target') || normalized.contains('advanced target changes');
    }

    private static void addApprovedTargetCloneLabels(List<String> labels) {
        addUniqueCloneLabel(labels, APPROVED_TARGET_PARAMETER);
        addUniqueCloneLabel(labels, LEGACY_APPROVED_TARGET_PARAMETER);
        addUniqueCloneLabel(labels, LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER);
    }

    private static void addCloneLookupKey(Set<String> keys, String label, String classification) {
        if (keys == null || String.isBlank(label)) {
            return;
        }
        keys.add(buildCloneRowKey(label, classification));
        String normalizedClassification = normalizeCloneClassification(classification);
        if (normalizedClassification == 'total') {
            keys.add(buildCloneRowKey(label, null));
        }
    }

    private static Boolean shouldCloneParameterRow(GWB_Month__c row, CloneConfigAllowlist allowlist) {
        return row != null &&
            allowlist != null &&
            allowlist.hasConfig &&
            allowlist.parameterKeys.contains(buildCloneRowKey(normalizeCloneParameterLabel(row.Parameter__c), row.Classification__c));
    }

    private static Boolean shouldCloneDriverRow(GWB_Month__c row, CloneConfigAllowlist allowlist) {
        return row != null &&
            allowlist != null &&
            allowlist.hasConfig &&
            allowlist.driverKeys.contains(buildCloneRowKey(normalizeCloneDriverValue(row.Driver__c), row.Classification__c));
    }

    private static String buildCloneRowKey(String label, String classification) {
        return normalizeCloneText(label) + '|' + normalizeCloneClassification(classification);
    }

    private static Set<String> buildCloneSectorFilters(String sectorValue) {
        Set<String> filters = new Set<String>();
        String normalizedSector = normalizeCloneText(sectorValue);
        if (String.isBlank(normalizedSector)) {
            return filters;
        }
        filters.add(normalizedSector);
        if (normalizedSector == 'press' || normalizedSector == 'stamping') {
            filters.add('press');
            filters.add('stamping');
        }
        return filters;
    }

    private static String normalizeCloneText(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static Boolean isCloneFormulaLine(String lineType) {
        return !String.isBlank(lineType) && lineType.trim().toLowerCase() == 'formula';
    }

    private static Boolean isCloneTotalLine(String lineType) {
        return !String.isBlank(lineType) && lineType.trim().toLowerCase() == 'total';
    }

    private static String normalizeCloneParameterLabel(String parameterValue) {
        if (String.isBlank(parameterValue)) {
            return parameterValue;
        }
        String normalized = parameterValue.trim();
        if (normalized == 'Absenteeism % + Summer VRO%') {
            return 'Absenteeism % + Summer VRO %';
        }
        if (normalized == 'ST Hours (inc. Add\'l ST Hours below)') {
            return 'ST Hours (inc. Add\'l ST Hours)';
        }
        if (normalized == 'NSOT Hours (NSOT % = NSOT / (ST + SOT)') {
            return 'NSOT Hours';
        }
        if (normalized == 'Additional Straight Time Hours (downweeks, etc)') {
            return 'Additional Straight Time Hours';
        }
        if (normalized == 'Calculated Volume including SOT days' ||
            normalized == 'Calculated Volume incl. SOT days') {
            return 'Calculated Volume incl. SOT';
        }
        if (normalized == APPROVED_TARGET_PARAMETER ||
            normalized == LEGACY_APPROVED_TARGET_PARAMETER ||
            normalized == LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER) {
            return APPROVED_TARGET_PARAMETER;
        }
        return normalized;
    }

    private static String normalizeCloneClassification(String classification) {
        String normalized = normalizeCloneText(classification);
        if (normalized == 'ost') {
            return 'ots';
        }
        if (normalized == 'sk' || normalized == 'skilled') {
            return 'skilled';
        }
        if (normalized == 'sal' || normalized == 'salary' || normalized == 'salaried') {
            return 'salaried';
        }
        if (normalized == 'total') {
            return 'total';
        }
        return normalized;
    }

    private static String normalizeCloneDriverValue(String driverValue) {
        if (String.isBlank(driverValue)) {
            return driverValue;
        }
        String trimmedDriver = driverValue.trim();
        if (trimmedDriver == 'Vac. Replacement' || trimmedDriver == 'Vacation Coverage') {
            return 'Vacation Replacement';
        }
        if (trimmedDriver == 'Others/Excess') {
            return 'Other/Excess';
        }
        return trimmedDriver;
    }

    private static Map<Id, Map<String, GWB_Month__c>> loadPreviousPublishedRowsBySourceTarget(
        List<GWB_Year__c> sourceTargets,
        Map<Id, List<GWB_Month__c>> monthsByTargetId
    ) {
        Map<Id, Map<String, GWB_Month__c>> result = new Map<Id, Map<String, GWB_Month__c>>();
        if (sourceTargets == null || sourceTargets.isEmpty()) {
            return result;
        }

        for (GWB_Year__c sourceTarget : sourceTargets) {
            if (sourceTarget == null || sourceTarget.Plant__c == null || String.isBlank(sourceTarget.Sector__c) || String.isBlank(sourceTarget.Year__c)) {
                continue;
            }

            Id previousLockedTargetId = loadPreviousLockedTargetId(
                sourceTarget.Plant_Sector__c,
                sourceTarget.Plant__c,
                sourceTarget.Sector__c,
                sourceTarget.Year__c
            );
            if (previousLockedTargetId == null) {
                continue;
            }

            Set<String> parameters = new Set<String>();
            List<GWB_Month__c> sourceMonths = monthsByTargetId.get(sourceTarget.Id);
            if (sourceMonths == null) {
                continue;
            }
            for (GWB_Month__c sourceMonth : sourceMonths) {
                if (sourceMonth != null && !String.isBlank(sourceMonth.Parameter__c)) {
                    parameters.add(sourceMonth.Parameter__c);
                }
            }
            if (parameters.isEmpty()) {
                continue;
            }

            Map<String, GWB_Month__c> publishedRowsByKey = new Map<String, GWB_Month__c>();
            for (GWB_Month__c publishedRow : [
                SELECT Id, Parameter__c, Classification__c,
                       Prev_Dec_Number__c, Prev_Dec_Decimal__c, Prev_Dec_Percent__c,
                       Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c,
                       Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                       Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c
                FROM GWB_Month__c
                WHERE GWB_Year__c = :previousLockedTargetId
                AND Parameter__c IN :parameters
            ]) {
                publishedRowsByKey.put(buildPublishedMonthKey(publishedRow.Parameter__c, publishedRow.Classification__c), publishedRow);
            }

            result.put(sourceTarget.Id, publishedRowsByKey);
        }

        return result;
    }

    private static Id loadPreviousLockedTargetId(Id plantSectorId, Id plantId, String sector, String targetYear) {
        if (plantSectorId == null || plantId == null || String.isBlank(sector) || String.isBlank(targetYear)) {
            return null;
        }

        String previousYear = String.valueOf(Integer.valueOf(targetYear) - 1);
        List<GWB_Year__c> previousTargets = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = :TARGET_RECORD_TYPE
            AND Plant_Sector__c = :plantSectorId
            AND Plant__c = :plantId
            AND Sector__c = :sector
            AND Status__c = :LOCKED_STATUS
            AND Year__c = :previousYear
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return previousTargets.isEmpty() ? null : previousTargets[0].Id;
    }

    private static void applyPublishedPrevDecValues(
        GWB_Month__c clonedMonth,
        Map<String, GWB_Month__c> publishedRowsByKey,
        GWB_Month__c sourceMonth
    ) {
        if (clonedMonth == null || sourceMonth == null || publishedRowsByKey == null || String.isBlank(sourceMonth.Parameter__c)) {
            return;
        }

        GWB_Month__c publishedRow = publishedRowsByKey.get(
            buildPublishedMonthKey(sourceMonth.Parameter__c, sourceMonth.Classification__c)
        );
        if (publishedRow == null && !String.isBlank(sourceMonth.Classification__c)) {
            publishedRow = publishedRowsByKey.get(buildPublishedMonthKey(sourceMonth.Parameter__c, null));
        }
        if (publishedRow == null) {
            return;
        }

        String valueType = inferSharedValueType(sourceMonth);
        if (valueType == 'decimal') {
            clonedMonth.Prev_Dec_Decimal__c = getPublishedDecimalBaseline(publishedRow);
        } else if (valueType == 'percent') {
            clonedMonth.Prev_Dec_Percent__c = getPublishedPercentBaseline(publishedRow);
        } else {
            clonedMonth.Prev_Dec_Number__c = getPublishedNumberBaseline(publishedRow);
        }
    }

    private static void clearCurrentYearMonthValues(GWB_Month__c row) {
        if (row == null) {
            return;
        }
        for (String fieldName : MONTH_NUMBER_FIELDS) {
            row.put(fieldName, null);
        }
        for (String fieldName : MONTH_DECIMAL_FIELDS) {
            row.put(fieldName, null);
        }
        for (String fieldName : MONTH_PERCENT_FIELDS) {
            row.put(fieldName, null);
        }
        row.Avg_Total__c = null;
        row.Annual_TotalDecimal1__c = null;
        row.Annual_TotalNumber1__c = null;
        row.Annual_TotalPercent1__c = null;
    }

    private static void syncClonedBaseHeadcountRows(
        List<GWB_Month__c> clonedMonths,
        List<GWB_Month__c> clonedDriverRows
    ) {
        if (clonedMonths == null || clonedMonths.isEmpty()) {
            return;
        }

        Map<String, GWB_Month__c> monthsByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c clonedMonth : clonedMonths) {
            if (clonedMonth == null || String.isBlank(clonedMonth.Parameter__c)) {
                continue;
            }
            monthsByKey.put(buildPublishedMonthKey(clonedMonth.Parameter__c, clonedMonth.Classification__c), clonedMonth);
        }

        for (String classification : MANPOWER_CLASSIFICATIONS) {
            GWB_Month__c baseRow = monthsByKey.get(buildPublishedMonthKey(BASE_HEADCOUNT_PARAMETER, classification));
            if (baseRow == null) {
                continue;
            }

            GWB_Month__c approvedRow = monthsByKey.get(buildPublishedMonthKey(APPROVED_TARGET_PARAMETER, classification));
            if (approvedRow == null) {
                approvedRow = monthsByKey.get(buildPublishedMonthKey(LEGACY_APPROVED_TARGET_PARAMETER, classification));
            }
            if (approvedRow == null) {
                approvedRow = monthsByKey.get(buildPublishedMonthKey(LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER, classification));
            }
            Decimal runningTotal = safeDecimal(baseRow.Prev_Dec_Number__c) + safeDecimal(approvedRow?.Prev_Dec_Number__c);
            for (String fieldName : MONTH_NUMBER_FIELDS) {
                runningTotal += sumTotalManpowerDriverValue(clonedDriverRows, classification, fieldName);
                baseRow.put(fieldName, runningTotal);
            }
        }
    }

    private static Decimal sumTotalManpowerDriverValue(
        List<GWB_Month__c> driverRows,
        String classification,
        String fieldName
    ) {
        Decimal total = 0;
        if (driverRows == null || String.isBlank(fieldName)) {
            return total;
        }

        for (GWB_Month__c driverRow : driverRows) {
            if (driverRow == null ||
                driverRow.Classification__c != classification ||
                !TOTAL_MANPOWER_DRIVER_NAMES.contains(driverRow.Driver__c)) {
                continue;
            }
            total += safeDecimal((Decimal) driverRow.get(fieldName));
        }
        return total;
    }

    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String buildPublishedMonthKey(String parameter, String classification) {
        return String.valueOf(parameter) + '|' + String.valueOf(classification);
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

    private static Decimal getPublishedNumberBaseline(GWB_Month__c row) {
        return row.Dec_Number__c != null ? row.Dec_Number__c : row.Prev_Dec_Number__c;
    }

    private static Decimal getPublishedDecimalBaseline(GWB_Month__c row) {
        return row.Dec_Decimal__c != null ? row.Dec_Decimal__c : row.Prev_Dec_Decimal__c;
    }

    private static Decimal getPublishedPercentBaseline(GWB_Month__c row) {
        return row.Dec_Percent__c != null ? row.Dec_Percent__c : row.Prev_Dec_Percent__c;
    }

    @AuraEnabled
    public static DeleteDraftBudgetResult deleteDraftBudget(Id draftBudgetId) {
        if (draftBudgetId == null) {
            throw new AuraHandledException('Select a draft budget before deleting.');
        }

        GWB_Year__c draftBudget = [
            SELECT Id, Name, Status__c, RecordType.DeveloperName
            FROM GWB_Year__c
            WHERE Id = :draftBudgetId
            LIMIT 1
        ];

        if (draftBudget.RecordType == null || draftBudget.RecordType.DeveloperName != BUDGET_RECORD_TYPE) {
            throw new AuraHandledException('Only Budget draft records can be deleted from this screen.');
        }

        if (draftBudget.Status__c != DRAFT_STATUS) {
            throw new AuraHandledException('Only draft budget records can be deleted from this screen.');
        }

        delete draftBudget;

        DeleteDraftBudgetResult result = new DeleteDraftBudgetResult();
        result.deletedDraftBudgetId = draftBudget.Id;
        result.deletedDraftBudgetName = draftBudget.Name;
        return result;
    }

    @AuraEnabled
    public static DeleteTargetResult deleteTarget(Id targetId) {
        if (targetId == null) {
            throw new AuraHandledException('Select a target before deleting.');
        }

        GWB_Year__c targetRecord = [
            SELECT Id, Name, Status__c, RecordType.DeveloperName
            FROM GWB_Year__c
            WHERE Id = :targetId
            LIMIT 1
        ];

        if (targetRecord.RecordType == null || targetRecord.RecordType.DeveloperName != TARGET_RECORD_TYPE) {
            throw new AuraHandledException('Only target records can be deleted from this screen.');
        }

        if (targetRecord.Status__c != DRAFT_STATUS) {
            throw new AuraHandledException('Only Draft target records can be deleted.');
        }

        delete targetRecord;

        DeleteTargetResult result = new DeleteTargetResult();
        result.deletedTargetId = targetRecord.Id;
        result.deletedTargetName = targetRecord.Name;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getTargetStatusUpdateOptions() {
        if (isIndustrialEngineerUser() || isPlantViewerUser()) {
            return new List<PicklistOption>();
        }
        if (isPlantAdminLikeUser()) {
            return new List<PicklistOption>{
                new PicklistOption(PLANT_REVIEW_COMPLETE_STATUS, PLANT_REVIEW_COMPLETE_STATUS)
            };
        }
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult describe = GWB_Year__c.Status__c.getDescribe();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String value = entry.getValue();
            if (value == 'Draft' || value == 'Published' || value == 'Locked') {
                continue;
            }
            options.add(new PicklistOption(entry.getLabel(), value));
        }
        return options;
    }

    @AuraEnabled
    public static UpdateStatusResult updateTargetStatuses(List<Id> targetIds, String newStatus) {
        if (targetIds == null || targetIds.isEmpty()) {
            throw new AuraHandledException('Select at least one target draft to update status.');
        }
        if (String.isBlank(newStatus)) {
            throw new AuraHandledException('Select a target status.');
        }
        if (newStatus == 'Draft' || newStatus == 'Published') {
            throw new AuraHandledException('Draft/Published statuses cannot be selected for mass update.');
        }
        if (isIndustrialEngineerUser() || isPlantViewerUser()) {
            throw new AuraHandledException('You do not have access to update target status from this screen.');
        }
        if (isPlantAdminLikeUser() && newStatus != PLANT_REVIEW_COMPLETE_STATUS) {
            throw new AuraHandledException('Plant Admin and Backup Plant Admin users can only update status to Plant Review Complete.');
        }

        Set<Id> uniqueIds = new Set<Id>(targetIds);

        List<GWB_Year__c> allTargets = [
            SELECT Id, Name, Status__c, RecordType.DeveloperName
            FROM GWB_Year__c
            WHERE Id IN :uniqueIds
            AND RecordType.DeveloperName = :TARGET_RECORD_TYPE
        ];

        // Skip Published/Locked targets; only update the rest
        List<GWB_Year__c> targetsToUpdate = new List<GWB_Year__c>();
        List<String> skippedTargetNames = new List<String>();
        for (GWB_Year__c t : allTargets) {
            if (t.Status__c == PUBLISHED_STATUS || t.Status__c == LOCKED_STATUS) {
                skippedTargetNames.add(t.Name);
            } else if (isPlantAdminLikeUser() && t.Status__c != PLANT_REVIEW_STATUS) {
                skippedTargetNames.add(t.Name);
            } else {
                t.Status__c = newStatus;
                targetsToUpdate.add(t);
            }
        }

        if (!targetsToUpdate.isEmpty()) {
            update targetsToUpdate;
        }

        UpdateStatusResult result = new UpdateStatusResult();
        result.updatedCount = targetsToUpdate.size();
        result.skippedTargetNames = skippedTargetNames;
        return result;
    }

    @AuraEnabled
    public static PublishResult publishSelectedTargets(List<Id> targetIds) {
        if (isPlantScopedTargetUser()) {
            throw new AuraHandledException('You do not have access to publish target records from this screen.');
        }
        if (targetIds == null || targetIds.isEmpty()) {
            throw new AuraHandledException('Select at least one target to publish.');
        }

        Set<Id> uniqueIds = new Set<Id>(targetIds);
        List<GWB_Year__c> selectedTargets = [
            SELECT Id, Status__c, RecordType.DeveloperName
            FROM GWB_Year__c
            WHERE Id IN :uniqueIds
            AND RecordType.DeveloperName = :TARGET_RECORD_TYPE
        ];

        List<GWB_Year__c> targetsToPublish = new List<GWB_Year__c>();
        for (GWB_Year__c targetRecord : selectedTargets) {
            if (targetRecord.Status__c == FINANCE_APPROVED_STATUS) {
                targetRecord.Status__c = PUBLISHED_STATUS;
                targetsToPublish.add(targetRecord);
            }
        }

        if (!targetsToPublish.isEmpty()) {
            update targetsToPublish;
        }

        PublishResult result = new PublishResult();
        result.updatedCount = targetsToPublish.size();
        result.skippedCount = uniqueIds.size() - targetsToPublish.size();
        return result;
    }

    private static String buildPlantSectorKey(Id plantId, String sector) {
        return String.valueOf(plantId) + '|' + String.valueOf(sector);
    }

    private static void applyScheduledVolumeValues(
        GWB_Month__c targetMonth,
        Decimal prevYearDec,
        Map<String, Decimal> scheduledVolumes
    ) {
        Map<String, Decimal> monthlyVolumes = scheduledVolumes == null
            ? new Map<String, Decimal>()
            : scheduledVolumes;
        targetMonth.Prev_Dec_Number__c = prevYearDec;
        targetMonth.Jan_Number__c = monthlyVolumes.containsKey('jan') ? monthlyVolumes.get('jan') : 0;
        targetMonth.Feb_Number__c = monthlyVolumes.containsKey('feb') ? monthlyVolumes.get('feb') : 0;
        targetMonth.Mar_Number__c = monthlyVolumes.containsKey('mar') ? monthlyVolumes.get('mar') : 0;
        targetMonth.Apr_Number__c = monthlyVolumes.containsKey('apr') ? monthlyVolumes.get('apr') : 0;
        targetMonth.May_Number__c = monthlyVolumes.containsKey('may') ? monthlyVolumes.get('may') : 0;
        targetMonth.Jun_Number__c = monthlyVolumes.containsKey('jun') ? monthlyVolumes.get('jun') : 0;
        targetMonth.Jul_Number__c = monthlyVolumes.containsKey('jul') ? monthlyVolumes.get('jul') : 0;
        targetMonth.Aug_Number__c = monthlyVolumes.containsKey('aug') ? monthlyVolumes.get('aug') : 0;
        targetMonth.Sep_Number__c = monthlyVolumes.containsKey('sep') ? monthlyVolumes.get('sep') : 0;
        targetMonth.Oct_Number__c = monthlyVolumes.containsKey('oct') ? monthlyVolumes.get('oct') : 0;
        targetMonth.Nov_Number__c = monthlyVolumes.containsKey('nov') ? monthlyVolumes.get('nov') : 0;
        targetMonth.Dec_Number__c = monthlyVolumes.containsKey('dec') ? monthlyVolumes.get('dec') : 0;
    }

    private static String buildTargetDisplayName(String yearValue, String versionValue, String fallbackName) {
        String displayName = '';
        if (String.isNotBlank(yearValue)) {
            displayName = yearValue.trim();
        }
        if (String.isNotBlank(versionValue)) {
            displayName = String.isNotBlank(displayName)
                ? displayName + ' ' + versionValue.trim()
                : versionValue.trim();
        }
        return String.isNotBlank(displayName) ? displayName : fallbackName;
    }

    private static String buildTargetVersion(String yearValue, String versionValue) {
        return String.isBlank(versionValue) || String.isBlank(yearValue)
            ? normalizeVersion(versionValue)
            : yearValue + ' ' + normalizeVersion(versionValue);
    }

    private static String normalizeVersion(String versionValue) {
        if (String.isBlank(versionValue)) {
            return '';
        }
        return versionValue.replace('%2B', '+');
    }

    /**
     * Loads the Target_Generation__mdt configuration record.
     * Falls back to null (callers apply safe defaults) if no record exists.
     */
    private static Target_Generation__mdt loadTargetGenerationConfig() {
        List<Target_Generation__mdt> configs = [
            SELECT Generation_Start_Month__c, Generation_End_Month__c,
                   Exclude_Start_Month__c, Exclude_End_Month__c
            FROM Target_Generation__mdt
            WHERE DeveloperName = :TARGET_GENERATION_RECORD
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    /**
     * Computes the rolling target year driven by metadata:
     *   - If today's month == Generation_End_Month → current year (e.g. January 2027 → "2027")
     *   - Otherwise → next year                    (e.g. May 2026 → "2027")
     * Defaults: Generation_End_Month = January (1)
     */
    @TestVisible
    private static String computeTargetYear(Target_Generation__mdt config) {
        Date today = Date.today();
        Integer genEndMonth = monthNameToNumber(config?.Generation_End_Month__c);
        if (genEndMonth == null) genEndMonth = 1; // default: January
        return today.month() == genEndMonth
            ? String.valueOf(today.year())
            : String.valueOf(today.year() + 1);
    }

    /**
     * Returns true when the "New Target" generation window is open.
     * Open from Generation_Start_Month through the end of Generation_End_Month.
     * Defaults: Start = May (5), End = January (1).
     */
    private static Boolean isNewTargetWindowOpen(Target_Generation__mdt config) {
        Integer month = Date.today().month();
        Integer genStart = monthNameToNumber(config?.Generation_Start_Month__c);
        Integer genEnd   = monthNameToNumber(config?.Generation_End_Month__c);
        if (genStart == null) genStart = 5; // default: May
        if (genEnd   == null) genEnd   = 1; // default: January
        return month >= genStart || month == genEnd;
    }

    /**
     * Returns true when today falls inside the exclude window
     * (i.e. the period when the component should be hidden for non-admins).
     * Defaults: Exclude_Start = February (2), Exclude_End = April (4).
     */
    private static Boolean isInExcludeWindow(Target_Generation__mdt config) {
        Integer month = Date.today().month();
        Integer excStart = monthNameToNumber(config?.Exclude_Start_Month__c);
        Integer excEnd   = monthNameToNumber(config?.Exclude_End_Month__c);
        if (excStart == null) excStart = 2; // default: February
        if (excEnd   == null) excEnd   = 4; // default: April
        return month >= excStart && month <= excEnd;
    }

    /**
     * Converts a full month name (case-insensitive) to its 1-based number.
     * Returns null for unrecognised values.
     */
    private static Integer monthNameToNumber(String monthName) {
        if (String.isBlank(monthName)) return null;
        Map<String, Integer> monthMap = new Map<String, Integer>{
            'january'   => 1,  'february' => 2,  'march'     => 3,
            'april'     => 4,  'may'       => 5,  'june'      => 6,
            'july'      => 7,  'august'    => 8,  'september' => 9,
            'october'   => 10, 'november'  => 11, 'december'  => 12
        };
        return monthMap.get(monthName.toLowerCase().trim());
    }

    private static Boolean hasCustomPermission(String customPermissionApiName) {
        return String.isNotBlank(customPermissionApiName)
            && FeatureManagement.checkPermission(customPermissionApiName);
    }

    private static void enforceCloneAccess() {
        if (isPlantScopedTargetUser()) {
            throw new AuraHandledException('You do not have access to clone target records from this screen.');
        }
    }

    private static Boolean isPlantScopedTargetUser() {
        return isPlantAdminLikeUser() || isIndustrialEngineerUser() || isPlantViewerUser();
    }

    private static Boolean isPlantAdminLikeUser() {
        if (hasCustomPermission(PLANT_ADMIN_PERMISSION)) {
            return true;
        }
        String persona = getCurrentUserPersona();
        return persona.contains('plantadmin') || (persona.contains('backup') && persona.contains('plant'));
    }

    private static Boolean isIndustrialEngineerUser() {
        if (hasCustomPermission(INDUSTRIAL_ENGINEER_PERMISSION)) {
            return true;
        }
        return getCurrentUserPersona().contains('industrial_engineer');
    }

    private static Boolean isPlantViewerUser() {
        if (hasCustomPermission(PLANT_VIEWER_PERMISSION)) {
            return true;
        }
        return getCurrentUserPersona().contains('plant_viewer');
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
}