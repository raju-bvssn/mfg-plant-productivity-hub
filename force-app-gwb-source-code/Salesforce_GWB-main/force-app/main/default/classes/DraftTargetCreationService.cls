public with sharing class DraftTargetCreationService {
    private static final String TARGET_RECORD_TYPE = 'Target';
    private static final String DRAFT_STATUS = 'Draft';
    private static final String LOCKED_STATUS = 'Locked';
    private static final String CATEGORY_OP_PLAN = 'Op Plan';
    private static final String CATEGORY_HEADCOUNT = 'Headcount';
    private static final String CATEGORY_HOURS = 'Hours';
    private static final String SECTION_HOURS = 'Hours';
    private static final String VALUE_TYPE_VALUE = 'Value';
    private static final String VALUE_TYPE_TOTAL = 'Total';
    private static final String POLYMERS_SECTOR = 'Polymers';
    private static final String ASSEMBLY_SECTOR = 'Assembly';
    private static final String SCHEDULED_VOLUME_SECTION = 'Op Plan';
    private static final String MANPOWER_SECTION = 'Headcount';
    private static final String LEGACY_SCHEDULED_VOLUME_SECTION = 'Scheduled_Volume';
    private static final String LEGACY_MANPOWER_SECTION = 'Manpower';
    private static final String SCHEDULED_VOLUME_PARAMETER = 'Scheduled Volume';
    private static final String BASE_HEADCOUNT_PARAMETER = 'Base Headcount';
    private static final String BASE_HEADCOUNT_NON_SUPP_PARAMETER = 'Base Headcount (non SUPP, no Apprentices)';
    private static final String APPROVED_TARGET_PARAMETER = 'Previous YE Approved Target Changes';
    private static final String LEGACY_APPROVED_TARGET_PARAMETER = 'Approved Target';
    private static final String LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER = 'Advanced Target Changes';
    private static final String TOTAL_MANPOWER_PARAMETER = 'Total Manpower';
    private static final String TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER = 'Total Manpower (Include Target Changes)';
    private static final String VACATION_REPLACEMENT_DRIVER = 'Vacation Replacement';
    private static final String CALCULATED_VOLUME_PARAMETER = 'Calculated Volume incl. SOT';
    private static final String VOLUME_VARIANCE_PARAMETER = 'Volume Variance';
    private static final String ADDITIONAL_ST_ADJUSTMENT_PARAMETER = 'Additional Straight Time Hours Adjustment';
    private static final String ADDITIONAL_ST_HOURS_PARAMETER = 'Additional Straight Time Hours';
    private static final String COMBINED_ABSENCE_PARAMETER = 'Absenteeism % + Summer VRO %';
    private static final String ST_HOURS_INCLUDE_ADDITIONAL_ST_PARAMETER = 'ST Hours (inc. Add\'l ST Hours)';
    private static final String NSOT_HOURS_PARAMETER = 'NSOT Hours';
    private static final String HOURS_JUSTIFICATION_TABLE = 'hoursJustification';
    private static final String ADDITIONAL_ST_JUSTIFICATION_ROW_KEY = 'astjust-monthly';
    private static final List<String> MONTH_KEYS = new List<String>{
        'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
    };
    private static final String GPS_SECTOR_KEY = 'gps';
    private static final String STAMPING_SECTOR_KEY = 'stamping';
    private static final List<String> MANPOWER_CLASSIFICATIONS = new List<String>{ 'OTS', 'Skilled', 'Salaried' };
    private static final Set<String> CLASSIFICATION_SPLIT_PARAMETERS = new Set<String>{
        BASE_HEADCOUNT_PARAMETER,
        APPROVED_TARGET_PARAMETER,
        'Absenteeism %',
        'NSOT %',
        ADDITIONAL_ST_ADJUSTMENT_PARAMETER
    };
    private static final Set<String> PREVIOUS_DECEMBER_ONLY_PARAMETERS = new Set<String>{
        'Available Working Days/Month',
        'Production Working Days/Month',
        'EQ SOT Days'
    };
    private static final List<String> SHARED_TARGET_MONTH_PARAMETERS = new List<String>{
        'Crews',
        'Shifts',
        'Net/Net JPH',
        CALCULATED_VOLUME_PARAMETER,
        SCHEDULED_VOLUME_PARAMETER,
        VOLUME_VARIANCE_PARAMETER,
        'Paid Hours Per CREW',
        'Available Working Days/Month',
        'Production Working Days/Month',
        'EQ SOT Days',
        BASE_HEADCOUNT_PARAMETER,
        APPROVED_TARGET_PARAMETER,
        'Absenteeism %',
        'NSOT %',
        ADDITIONAL_ST_ADJUSTMENT_PARAMETER
    };
    private static final List<String> GPS_TARGET_MONTH_PARAMETERS = new List<String>{
        'Final Assembly Line JPH',
        'Daily Op Plan Volume',
        'SOT days (Weekends)',
        'EQ SOT Days (Additional Weekday hours)',
        'Total SOT Days'
    };
    private static final List<String> STAMPING_TARGET_MONTH_PARAMETERS = new List<String>{
        'Equivalent Units Volume',
        'Daily Op Plan Volume',
        'HARBOUR STROKES HPU',
        'Scheduled Volume Pieces',
        'Scheduled Volume Strokes',
        'Equivalent SOT %',
        'SOT percent from weekend days',
        'SOT from line time',
        'SOT equivalent days total'
    };

    private static Id cachedTargetRecordTypeId;

    public class DraftTargetProcessingException extends Exception {}

    public class ProcessingResult {
        public Integer successCount = 0;
        public Integer failureCount = 0;
        public List<String> failureMessages = new List<String>();
        public List<String> successMessages = new List<String>();
    }

    private class TargetCreationOutcome {
        Id targetId;
        String plantName;
        String sector;
        String targetYear;
        Id previousLockedTargetId;
        Integer uiConfigCount = 0;
        Integer createdMonthRowCount = 0;
        Integer populatedScheduledVolumeMonths = 0;
    }

    private class VacationCoverageSeed {
        Decimal vacationPercent;
        String entryMonthKey;
        String exitMonthKey;
    }

    public static ProcessingResult processPlantSectors(
        List<Plant_Sector__c> plantSectors,
        String versionValue,
        String programCode,
        String functionalArea
    ) {
        ProcessingResult result = new ProcessingResult();
        if (plantSectors == null || plantSectors.isEmpty()) {
            return result;
        }

        String normalizedVersionValue = normalizeVersion(versionValue);
        for (Plant_Sector__c plantSector : plantSectors) {
            Savepoint sp = Database.setSavepoint();
            try {
                TargetCreationOutcome outcome = createTargetForPlantSector(
                    plantSector,
                    normalizedVersionValue,
                    programCode,
                    functionalArea
                );
                result.successCount++;
                if (result.successMessages.size() < 25) {
                    result.successMessages.add(buildSuccessMessage(plantSector, outcome));
                }
            } catch (Exception e) {
                Database.rollback(sp);
                result.failureCount++;
                if (result.failureMessages.size() < 25) {
                    result.failureMessages.add(buildFailureMessage(plantSector, e));
                }
            }
        }

        return result;
    }

    private static TargetCreationOutcome createTargetForPlantSector(
        Plant_Sector__c plantSector,
        String versionValue,
        String programCode,
        String functionalArea
    ) {
        if (plantSector == null || plantSector.Plant__c == null) {
            throw new DraftTargetProcessingException('Plant Sector data is incomplete.');
        }
        if (plantSector.Id != null) {
            plantSector = [
                SELECT Id, Plant__c, Plant_Program__c, Program_Code__c, Functional_Area__c,
                       Auth_Sector__c, Plant__r.Name, Plant__r.Auth_Sector__c,
                       Plant__r.Vehicle_Brand__c, Plant__r.Auth_Site_Name__c
                FROM Plant_Sector__c
                WHERE Id = :plantSector.Id
                LIMIT 1
            ];
        }

        String resolvedSector = resolveSector(plantSector);

        if (String.isBlank(resolvedSector)) {
            throw new DraftTargetProcessingException('Plant Sector data is incomplete.');
        }

        String targetYear = String.valueOf(Date.today().year() + 1);
        Id previousLockedTargetId = loadPreviousLockedTargetId(plantSector.Id, plantSector.Plant__c, resolvedSector, targetYear);
        logInfo(
            'Starting target creation | PlantSectorId=' + plantSector.Id +
            ' | Plant=' + safeValue(plantSector.Plant__r != null ? plantSector.Plant__r.Name : null) +
            ' | Sector=' + safeValue(resolvedSector) +
            ' | TargetYear=' + targetYear +
            ' | PreviousLockedTargetId=' + safeValue(String.valueOf(previousLockedTargetId)) +
            ' | Version=' + safeValue(versionValue)
        );
        String resolvedProgramCode = String.isBlank(plantSector.Program_Code__c) ? programCode : plantSector.Program_Code__c;
        String resolvedFunctionalArea = String.isBlank(plantSector.Functional_Area__c) ? functionalArea : plantSector.Functional_Area__c;
        GWB_Year__c targetRecord = new GWB_Year__c(
            Plant_Sector__c = plantSector.Id,
            Plant__c = plantSector.Plant__c,
            Plant_Program__c = plantSector.Plant_Program__c,
            Sector__c = resolvedSector,
            Previous_Year_GWB__c = previousLockedTargetId,
            M_Schedule_Version__c = versionValue,
            Status__c = DRAFT_STATUS,
            Year__c = targetYear,
            Version__c = buildGwbVersionValue(versionValue, targetYear),
            RecordTypeId = getTargetRecordTypeId()
        );
        insert targetRecord;
        logInfo('Inserted target header | TargetId=' + targetRecord.Id + ' | PlantSectorId=' + plantSector.Id);

        Map<String, Decimal> scheduledVolumeByMonth = loadScheduledVolumeByMonth(
            plantSector,
            targetYear,
            versionValue,
            resolvedProgramCode,
            resolvedFunctionalArea
        );
        VacationCoverageSeed vacationCoverageSeed = loadVacationCoverageSeed(
            plantSector.Plant__c,
            resolvedSector,
            targetYear
        );
        List<Target_UI_Controller__mdt> targetUiConfigs = loadActiveTargetUiConfigs(resolvedSector);
        if (targetUiConfigs.isEmpty()) {
            logWarn(
                'No active Target UI Controller metadata found | TargetId=' + targetRecord.Id +
                ' | Sector=' + safeValue(resolvedSector)
            );
        }
        Map<String, GWB_Month__c> publishedMonthsByParameter = loadPublishedTargetMonths(
            previousLockedTargetId,
            extractPersistedParameterValues(targetUiConfigs)
        );
        Map<String, GWB_Month__c> publishedMonthsByDriver = loadPublishedTargetDrivers(previousLockedTargetId);
        List<GWB_Month__c> monthRows = buildTargetMonthRows(
            targetRecord,
            targetUiConfigs,
            publishedMonthsByParameter,
            publishedMonthsByDriver,
            scheduledVolumeByMonth,
            versionValue,
            vacationCoverageSeed
        );
        logInfo(
            'Prepared target month rows | TargetId=' + targetRecord.Id +
            ' | MetadataRows=' + targetUiConfigs.size() +
            ' | BaselineRows=' + publishedMonthsByParameter.size() +
            ' | MonthRowsToInsert=' + monthRows.size() +
            ' | ScheduledVolumeMonthsPopulated=' + countPopulatedMonths(scheduledVolumeByMonth)
        );
        if (!monthRows.isEmpty()) {
            insert monthRows;
            logInfo('Inserted target month rows | TargetId=' + targetRecord.Id + ' | InsertedRows=' + monthRows.size());
        } else {
            logWarn(
                'No month rows generated for target header | TargetId=' + targetRecord.Id +
                ' | Check metadata, picklists, and filters.'
            );
        }
        copyAdditionalStraightAdjustmentJustifications(previousLockedTargetId, targetRecord.Id);
        logInfo('Completed target creation | TargetId=' + targetRecord.Id);

        TargetCreationOutcome outcome = new TargetCreationOutcome();
        outcome.targetId = targetRecord.Id;
        outcome.plantName = plantSector.Plant__r != null ? plantSector.Plant__r.Name : null;
        outcome.sector = resolvedSector;
        outcome.targetYear = targetYear;
        outcome.previousLockedTargetId = previousLockedTargetId;
        outcome.uiConfigCount = targetUiConfigs.size();
        outcome.createdMonthRowCount = monthRows.size();
        outcome.populatedScheduledVolumeMonths = countPopulatedMonths(scheduledVolumeByMonth);
        return outcome;
    }

    private static Id loadPreviousLockedTargetId(Id plantSectorId, Id plantId, String sector, String targetYear) {
        String previousYear = String.isBlank(targetYear)
            ? String.valueOf(Date.today().year())
            : String.valueOf(Integer.valueOf(targetYear) - 1);
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

    private static Map<String, GWB_Month__c> loadPublishedTargetMonths(Id publishedTargetId, List<String> targetMonthParameters) {
        Map<String, GWB_Month__c> monthsByParameter = new Map<String, GWB_Month__c>();
        if (publishedTargetId == null || targetMonthParameters == null || targetMonthParameters.isEmpty()) {
            return monthsByParameter;
        }

        for (GWB_Month__c sourceRow : [
            SELECT Id, Section__c, Parameter__c, Classification__c,
                   Prev_Dec_Number__c, Prev_Dec_Decimal__c, Prev_Dec_Percent__c,
                   Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c,
                   Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                   Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :publishedTargetId
            AND Parameter__c IN :targetMonthParameters
        ]) {
            monthsByParameter.put(buildPublishedMonthKey(sourceRow.Parameter__c, sourceRow.Classification__c), sourceRow);
        }

        return monthsByParameter;
    }

    private static Map<String, GWB_Month__c> loadPublishedTargetDrivers(Id publishedTargetId) {
        Map<String, GWB_Month__c> monthsByDriver = new Map<String, GWB_Month__c>();
        if (publishedTargetId == null) {
            return monthsByDriver;
        }

        for (GWB_Month__c sourceRow : [
            SELECT Id, Driver__c, Classification__c, Prev_Dec_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :publishedTargetId
            AND Driver__c != null
        ]) {
            monthsByDriver.put(buildPublishedDriverKey(sourceRow.Driver__c, sourceRow.Classification__c), sourceRow);
        }

        return monthsByDriver;
    }

    private static Map<String, Decimal> loadScheduledVolumeByMonth(
        Plant_Sector__c plantSector,
        String targetYear,
        String versionValue,
        String programCode,
        String functionalArea
    ) {
        Map<String, Decimal> monthlyVolumes = initializeMonthlyVolumeMap();
        String resolvedSector = resolveSector(plantSector);
        if (plantSector == null || plantSector.Plant__c == null || String.isBlank(resolvedSector)) {
            return monthlyVolumes;
        }

        Id plantIdToUse = plantSector.Plant__c;
        Set<String> requiredVehicleBrands;
        if (POLYMERS_SECTOR.equalsIgnoreCase(resolvedSector)) {
            Plant__c sourcePlant = [
                SELECT Id, Auth_Site_Name__c
                FROM Plant__c
                WHERE Id = :plantSector.Plant__c
                LIMIT 1
            ];
            Plant__c assemblyPlant = getPolymersAssemblyPlant(sourcePlant.Auth_Site_Name__c);
            if (assemblyPlant == null) {
                return monthlyVolumes;
            }
            plantIdToUse = assemblyPlant.Id;
            requiredVehicleBrands = extractVehicleBrands(assemblyPlant.Vehicle_Brand__c);
        } else {
            requiredVehicleBrands = extractVehicleBrands(
                plantSector.Plant__r != null ? plantSector.Plant__r.Vehicle_Brand__c : null
            );
        }
        Boolean isGpsSector = resolvedSector == 'GPS';
        String normalizedProgramCode = String.isBlank(programCode) ? null : programCode.trim();
        String normalizedFunctionalArea = String.isBlank(functionalArea) ? null : functionalArea.trim();

        Set<String> versionFilterValues = buildVersionFilterValues(versionValue);
        String volumeSoql =
            'SELECT Month__c, Volume__c, Vehicle_Brand__c, Program_Code__c,Functional_Area__c' +
            ' FROM Plant_Volume__c' +
            ' WHERE Plant__c = :plantIdToUse' +
            ' AND Calendar_Year__c = :targetYear' +
            ' AND Data_Point_Value__c IN :versionFilterValues';
        if (!POLYMERS_SECTOR.equalsIgnoreCase(resolvedSector)) {
            volumeSoql += ' AND Sector__c = :resolvedSector';
        }
        for (Plant_Volume__c volumeRow : Database.query(volumeSoql)) {
            if (isGpsSector &&
                (volumeRow.Program_Code__c != normalizedProgramCode ||
                    volumeRow.Functional_Area__c != normalizedFunctionalArea)
            ) {
                continue;
            }
            if (!shouldIncludeScheduledVolumeRow(resolvedSector, volumeRow.Vehicle_Brand__c, requiredVehicleBrands)) {
                continue;
            }

            String monthKey = normalizeMonthKey(volumeRow.Month__c);
            if (monthKey == null) {
                continue;
            }

            addVolumeToMonth(monthlyVolumes, monthKey, volumeRow.Volume__c);
        }

        return monthlyVolumes;
    }

    public static Map<Id, Map<String, Decimal>> loadScheduledVolumeBySourceTarget(
        List<GWB_Year__c> sourceTargets,
        String versionValue
    ) {
        Map<Id, Map<String, Decimal>> volumesByTargetId = new Map<Id, Map<String, Decimal>>();
        if (sourceTargets == null || sourceTargets.isEmpty()) {
            return volumesByTargetId;
        }

        for (GWB_Year__c sourceTarget : sourceTargets) {
            volumesByTargetId.put(sourceTarget.Id, initializeMonthlyVolumeMap());
        }

        for (GWB_Year__c sourceTarget : sourceTargets) {
            if (sourceTarget.Plant__c == null || String.isBlank(sourceTarget.Sector__c) || String.isBlank(sourceTarget.Year__c)) {
                continue;
            }

            Id targetPlantId = sourceTarget.Plant__c;
            String targetSector = sourceTarget.Sector__c;
            String targetYear = sourceTarget.Year__c;
            Map<String, Decimal> monthlyVolumes = volumesByTargetId.get(sourceTarget.Id);
            Boolean isPolymersSector = POLYMERS_SECTOR.equalsIgnoreCase(targetSector);
            Set<String> requiredVehicleBrands;
            if (isPolymersSector) {
                List<Plant__c> sourcePlants = [
                    SELECT Auth_Site_Name__c
                    FROM Plant__c
                    WHERE Id = :targetPlantId
                    LIMIT 1
                ];
                if (sourcePlants.isEmpty() || String.isBlank(sourcePlants[0].Auth_Site_Name__c)) {
                    continue;
                }

                Plant__c assemblyPlant = getPolymersAssemblyPlant(sourcePlants[0].Auth_Site_Name__c);
                if (assemblyPlant == null) {
                    continue;
                }

                targetPlantId = assemblyPlant.Id;
                requiredVehicleBrands = extractVehicleBrands(assemblyPlant.Vehicle_Brand__c);
                if (requiredVehicleBrands.isEmpty()) {
                    continue;
                }
            } else {
                requiredVehicleBrands = extractVehicleBrands(
                    sourceTarget.Plant__r != null ? sourceTarget.Plant__r.Vehicle_Brand__c : null
                );
            }

            Set<String> versionFilterValues = buildVersionFilterValues(versionValue);
            String soql =
                'SELECT Month__c, Volume__c, Vehicle_Brand__c' +
                ' FROM Plant_Volume__c' +
                ' WHERE Plant__c = :targetPlantId' +
                ' AND Calendar_Year__c = :targetYear' +
                ' AND Data_Point_Value__c IN :versionFilterValues';
            if (!isPolymersSector) {
                soql += ' AND Sector__c = :targetSector';
            }

            for (Plant_Volume__c volumeRow : Database.query(soql)) {
                if (!shouldIncludeScheduledVolumeRow(targetSector, volumeRow.Vehicle_Brand__c, requiredVehicleBrands)) {
                    continue;
                }

                String monthKey = normalizeMonthKey(volumeRow.Month__c);
                if (monthKey == null) {
                    continue;
                }

                addVolumeToMonth(monthlyVolumes, monthKey, volumeRow.Volume__c);
            }
        }

        return volumesByTargetId;
    }

    public static Map<Id, Decimal> loadPrevYearScheduledVolumeDecByTarget(List<GWB_Year__c> sourceTargets) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        if (sourceTargets == null || sourceTargets.isEmpty()) {
            return result;
        }

        Set<Id> sourceTargetIds = new Set<Id>();
        for (GWB_Year__c sourceTarget : sourceTargets) {
            if (sourceTarget != null && sourceTarget.Id != null) {
                sourceTargetIds.add(sourceTarget.Id);
            }
        }
        if (sourceTargetIds.isEmpty()) {
            return result;
        }

        for (GWB_Year__c t : [
            SELECT Id, Plant_Sector__c, Plant__c, Plant__r.Vehicle_Brand__c, Sector__c, Year__c
            FROM GWB_Year__c
            WHERE Id IN :sourceTargetIds
        ]) {
            if (t.Plant__c == null || String.isBlank(t.Sector__c) || String.isBlank(t.Year__c)) {
                continue;
            }
            Id prevTargetId = loadPreviousLockedTargetId(t.Plant_Sector__c, t.Plant__c, t.Sector__c, t.Year__c);
            Map<String, GWB_Month__c> monthsByParam = loadPublishedTargetMonths(
                prevTargetId,
                new List<String>{ SCHEDULED_VOLUME_PARAMETER }
            );
            GWB_Month__c prevRow = monthsByParam.get(buildPublishedMonthKey(SCHEDULED_VOLUME_PARAMETER, null));
            result.put(t.Id, prevRow != null ? getPublishedNumberBaseline(prevRow) : null);
        }
        return result;
    }

    private static Boolean shouldIncludeScheduledVolumeRow(
        String sector,
        String vehicleBrand,
        Set<String> requiredVehicleBrands
    ) {
        if (!POLYMERS_SECTOR.equalsIgnoreCase(sector)) {
            return true;
        }
        if (requiredVehicleBrands == null || requiredVehicleBrands.isEmpty()) {
            return false;
        }

        Set<String> volumeRowBrands = extractVehicleBrands(vehicleBrand);
        if (volumeRowBrands.isEmpty()) {
            return false;
        }

        for (String brand : volumeRowBrands) {
            if (requiredVehicleBrands.contains(brand)) {
                return true;
            }
        }
        return false;
    }

    private static void addVolumeToMonth(Map<String, Decimal> monthlyVolumes, String monthKey, Decimal volume) {
        if (monthlyVolumes == null || String.isBlank(monthKey)) {
            return;
        }

        monthlyVolumes.put(
            monthKey,
            (monthlyVolumes.get(monthKey) == null ? 0 : monthlyVolumes.get(monthKey)) +
            (volume == null ? 0 : volume)
        );
    }

    private static Set<String> buildVersionFilterValues(String versionValue) {
        Set<String> versionValues = new Set<String>();
        if (String.isBlank(versionValue)) {
            return versionValues;
        }

        String normalizedVersion = normalizeVersion(versionValue).trim();
        versionValues.add(normalizedVersion);

        List<String> versionParts = normalizedVersion.split('\\+');
        if (versionParts.size() == 2) {
            try {
                versionValues.add(String.valueOf(Integer.valueOf(versionParts[0])) + '+' + String.valueOf(Integer.valueOf(versionParts[1])));
            } catch (Exception ignored) {
                // Keep the original value when the version is not numeric M+Schedule format.
            }
        }
        return versionValues;
    }

    private static List<GWB_Month__c> buildTargetMonthRows(
        GWB_Year__c targetRecord,
        List<Target_UI_Controller__mdt> targetUiConfigs,
        Map<String, GWB_Month__c> publishedMonthsByParameter,
        Map<String, GWB_Month__c> publishedMonthsByDriver,
        Map<String, Decimal> scheduledVolumeByMonth,
        String versionValue,
        VacationCoverageSeed vacationCoverageSeed
    ) {
        List<GWB_Month__c> rowsToInsert = new List<GWB_Month__c>();
        if (targetUiConfigs == null || targetUiConfigs.isEmpty()) {
            return rowsToInsert;
        }

        Set<String> seenSeedKeys = new Set<String>();
        for (Target_UI_Controller__mdt config : targetUiConfigs) {
            if (config == null) {
                continue;
            }
            if (!isPersistableCreationConfig(config)) {
                continue;
            }
            Boolean isPersistedTotalRow = config.Source_Type__c == 'Derived' && config.UI_Line_Type__c == 'Total';
            if (config.Source_Type__c == 'Derived' && !isPersistedTotalRow) {
                continue;
            }
            String seedKey = buildUiSeedKey(config);
            if (seenSeedKeys.contains(seedKey)) {
                continue;
            }
            seenSeedKeys.add(seedKey);

            if (config.Source_Type__c == 'Driver') {
                rowsToInsert.add(buildConfiguredDriverRow(targetRecord, config, publishedMonthsByDriver, versionValue));
                continue;
            }

            rowsToInsert.add(
                buildConfiguredParameterRow(
                    targetRecord,
                    config,
                    publishedMonthsByParameter,
                    scheduledVolumeByMonth,
                    versionValue
                )
            );
        }
        applyAssemblyVacationCoverageSeed(rowsToInsert, publishedMonthsByParameter, targetRecord.Sector__c, vacationCoverageSeed);
        return rowsToInsert;
    }

    private static void applyAssemblyVacationCoverageSeed(
        List<GWB_Month__c> rowsToInsert,
        Map<String, GWB_Month__c> publishedMonthsByParameter,
        String sector,
        VacationCoverageSeed seed
    ) {
        if (rowsToInsert == null || rowsToInsert.isEmpty() || seed == null) {
            return;
        }
        if (normalizeTargetSectorKey(sector) != 'assembly') {
            return;
        }
        if (seed.vacationPercent == null || seed.vacationPercent <= 0 ||
            String.isBlank(seed.entryMonthKey) || String.isBlank(seed.exitMonthKey)) {
            return;
        }

        GWB_Month__c vacationRow;
        GWB_Month__c baseRow;
        Map<String, GWB_Month__c> adjustmentRowsByKey = new Map<String, GWB_Month__c>();

        for (GWB_Month__c row : rowsToInsert) {
            if (row == null || row.Classification__c != 'OTS') {
                continue;
            }
            if (isVacationDriverFamily(row.Driver__c)) {
                vacationRow = row;
                continue;
            }
            if (isBaseHeadcountFamily(row.Parameter__c)) {
                baseRow = row;
                continue;
            }
            if (String.isNotBlank(row.Driver__c) && row.Category__c == CATEGORY_HEADCOUNT) {
                adjustmentRowsByKey.put(row.Driver__c, row);
            }
        }

        if (baseRow == null) {
            baseRow = getPublishedTargetMonthOrFallback(
                publishedMonthsByParameter,
                BASE_HEADCOUNT_NON_SUPP_PARAMETER,
                'OTS',
                null
            );
        }
        if (vacationRow == null) {
            return;
        }

        Map<String, Decimal> totalBeforeVacation = buildTotalManpowerBeforeVacation(
            baseRow,
            adjustmentRowsByKey
        );
        Decimal entryBase = totalBeforeVacation.containsKey(seed.entryMonthKey)
            ? totalBeforeVacation.get(seed.entryMonthKey)
            : 0;
        Decimal seededValue = entryBase == null
            ? 0
            : (entryBase * (seed.vacationPercent / 100)).setScale(0, System.RoundingMode.HALF_UP);

        initializeNumberMonths(vacationRow, 0);
        setNumberMonth(vacationRow, seed.entryMonthKey, seededValue);
        setNumberMonth(vacationRow, seed.exitMonthKey, seededValue * -1);
    }

    private static Map<String, Decimal> buildTotalManpowerBeforeVacation(
        GWB_Month__c baseRow,
        Map<String, GWB_Month__c> adjustmentRowsByKey
    ) {
        Map<String, Decimal> totalsByMonth = new Map<String, Decimal>();
        Decimal previousDecemberTotal = getNumberValue(baseRow, 'prevDec');
        totalsByMonth.put('prevDec', previousDecemberTotal);
        Decimal runningTotal = previousDecemberTotal;
        for (String monthKey : MONTH_KEYS) {
            Decimal adjustmentTotal = 0;
            for (GWB_Month__c adjustmentRow : adjustmentRowsByKey.values()) {
                adjustmentTotal += getNumberValue(adjustmentRow, monthKey);
            }
            runningTotal += adjustmentTotal;
            totalsByMonth.put(monthKey, runningTotal);
        }
        return totalsByMonth;
    }

    private static Decimal getNumberValue(GWB_Month__c row, String monthKey) {
        if (row == null) {
            return 0;
        }
        if (monthKey == 'prevDec') return row.Prev_Dec_Number__c == null ? 0 : row.Prev_Dec_Number__c;
        if (monthKey == 'jan') return row.Jan_Number__c == null ? 0 : row.Jan_Number__c;
        if (monthKey == 'feb') return row.Feb_Number__c == null ? 0 : row.Feb_Number__c;
        if (monthKey == 'mar') return row.Mar_Number__c == null ? 0 : row.Mar_Number__c;
        if (monthKey == 'apr') return row.Apr_Number__c == null ? 0 : row.Apr_Number__c;
        if (monthKey == 'may') return row.May_Number__c == null ? 0 : row.May_Number__c;
        if (monthKey == 'jun') return row.Jun_Number__c == null ? 0 : row.Jun_Number__c;
        if (monthKey == 'jul') return row.Jul_Number__c == null ? 0 : row.Jul_Number__c;
        if (monthKey == 'aug') return row.Aug_Number__c == null ? 0 : row.Aug_Number__c;
        if (monthKey == 'sep') return row.Sep_Number__c == null ? 0 : row.Sep_Number__c;
        if (monthKey == 'oct') return row.Oct_Number__c == null ? 0 : row.Oct_Number__c;
        if (monthKey == 'nov') return row.Nov_Number__c == null ? 0 : row.Nov_Number__c;
        if (monthKey == 'dec') return row.Dec_Number__c == null ? 0 : row.Dec_Number__c;
        return 0;
    }

    private static Boolean isBaseHeadcountFamily(String parameterValue) {
        String normalized = String.isBlank(parameterValue) ? '' : parameterValue.trim().toLowerCase();
        return normalized.startsWith('base headcount');
    }

    private static Boolean isApprovedTargetFamily(String parameterValue) {
        String normalized = String.isBlank(parameterValue) ? '' : parameterValue.trim().toLowerCase();
        return normalized.contains('approved target') || normalized.contains('advanced target changes');
    }

    private static Boolean isVacationDriverFamily(String driverValue) {
        String normalized = String.isBlank(driverValue) ? '' : driverValue.trim().toLowerCase();
        return normalized == 'vacation replacement' || normalized == 'vacation coverage' || normalized == 'vac. replacement';
    }

    private static void setNumberMonth(GWB_Month__c row, String monthKey, Decimal value) {
        if (row == null || String.isBlank(monthKey)) {
            return;
        }
        if (monthKey == 'jan') row.Jan_Number__c = value;
        else if (monthKey == 'feb') row.Feb_Number__c = value;
        else if (monthKey == 'mar') row.Mar_Number__c = value;
        else if (monthKey == 'apr') row.Apr_Number__c = value;
        else if (monthKey == 'may') row.May_Number__c = value;
        else if (monthKey == 'jun') row.Jun_Number__c = value;
        else if (monthKey == 'jul') row.Jul_Number__c = value;
        else if (monthKey == 'aug') row.Aug_Number__c = value;
        else if (monthKey == 'sep') row.Sep_Number__c = value;
        else if (monthKey == 'oct') row.Oct_Number__c = value;
        else if (monthKey == 'nov') row.Nov_Number__c = value;
        else if (monthKey == 'dec') row.Dec_Number__c = value;
    }

    private static GWB_Month__c buildConfiguredParameterRow(
        GWB_Year__c targetRecord,
        Target_UI_Controller__mdt config,
        Map<String, GWB_Month__c> publishedMonthsByParameter,
        Map<String, Decimal> scheduledVolumeByMonth,
        String versionValue
    ) {
        String parameterValue = normalizeTargetParameterLabel(
            String.isBlank(config.Source_Value__c) ? config.Parameter_Driver__c : config.Source_Value__c
        );
        if (config.Formula_Key__c == 'totalManpower') {
            parameterValue = TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER;
        }
        String persistedParameterValue = resolvePersistedParameterValue(parameterValue);
        String normalizedClassification = normalizeClassification(config.Classification__c);
        GWB_Month__c sourceRow = getPublishedTargetMonthOrFallback(
            publishedMonthsByParameter,
            parameterValue,
            normalizedClassification,
            config.Formula_Key__c
        );

        GWB_Month__c row = buildBaseTargetMonthRow(
            targetRecord,
            resolveStoredSection(config),
            persistedParameterValue,
            versionValue,
            toStoredClassification(normalizedClassification)
        );
        applyUiMetadataToTargetRow(row, config);

        String valueType = normalizeValueType(config.Value_Type__c, persistedParameterValue);
        if (persistedParameterValue == SCHEDULED_VOLUME_PARAMETER) {
            row = buildScheduledVolumeRow(targetRecord, sourceRow, scheduledVolumeByMonth, versionValue, toStoredClassification(normalizedClassification));
            applyUiMetadataToTargetRow(row, config);
            return row;
        }

        copyPrevDecFromPublishedDecember(row, sourceRow, valueType);
        if (shouldCarryForwardAcrossTargetYear(config, parameterValue)) {
            copyPublishedDecemberAcrossYear(row, sourceRow, valueType);
        }
        return row;
    }

    private static GWB_Month__c buildConfiguredDriverRow(
        GWB_Year__c targetRecord,
        Target_UI_Controller__mdt config,
        Map<String, GWB_Month__c> publishedMonthsByDriver,
        String versionValue
    ) {
        String driverValue = normalizeDriverValue(String.isBlank(config.Source_Value__c) ? config.Parameter_Driver__c : config.Source_Value__c);
        String normalizedClassification = normalizeClassification(config.Classification__c);
        GWB_Month__c row = new GWB_Month__c(
            GWB_Year__c = targetRecord.Id,
            Plant__c = targetRecord.Plant__c,
            Sector__c = targetRecord.Sector__c,
            Year__c = targetRecord.Year__c,
            Data_Point_Value__c = versionValue,
            Driver__c = driverValue,
            Classification__c = toStoredClassification(normalizedClassification)
        );
        applyUiMetadataToTargetRow(row, config);
        initializeNumberMonths(row, 0);
        GWB_Month__c sourceRow = publishedMonthsByDriver == null
            ? null
            : publishedMonthsByDriver.get(buildPublishedDriverKey(driverValue, normalizedClassification));
        if (sourceRow == null && String.isNotBlank(normalizedClassification)) {
            sourceRow = publishedMonthsByDriver == null
                ? null
                : publishedMonthsByDriver.get(buildPublishedDriverKey(driverValue, null));
        }
        if (sourceRow != null) {
            row.Prev_Dec_Number__c = getPublishedNumberBaseline(sourceRow);
        }
        return row;
    }

    private static void initializeNumberMonths(GWB_Month__c row, Decimal value) {
        row.Prev_Dec_Number__c = value;
        row.Jan_Number__c = value;
        row.Feb_Number__c = value;
        row.Mar_Number__c = value;
        row.Apr_Number__c = value;
        row.May_Number__c = value;
        row.Jun_Number__c = value;
        row.Jul_Number__c = value;
        row.Aug_Number__c = value;
        row.Sep_Number__c = value;
        row.Oct_Number__c = value;
        row.Nov_Number__c = value;
        row.Dec_Number__c = value;
    }

    private static void applyUiMetadataToTargetRow(GWB_Month__c row, Target_UI_Controller__mdt config) {
        row.Section__c = resolveStoredSection(config);
        row.Category__c = resolveStoredCategory(config);
        row.UI_Sequence__c = config.UI_Sequence__c;
        row.Value_Type__c = resolveStoredValueType(config);
    }

    private static Boolean shouldCarryForwardAcrossTargetYear(Target_UI_Controller__mdt config, String parameterValue) {
        if (config == null) {
            return false;
        }
        if (config.Source_Type__c != 'Parameter') {
            return false;
        }
        if (parameterValue == SCHEDULED_VOLUME_PARAMETER) {
            return false;
        }
        if (isApprovedTargetFamily(parameterValue)) {
            return false;
        }
        if (PREVIOUS_DECEMBER_ONLY_PARAMETERS.contains(parameterValue)) {
            return false;
        }
        if (config.UI_Line_Type__c == 'Total') {
            return false;
        }
        if (config.UI_Line_Type__c == 'Formula' && parameterValue != TOTAL_MANPOWER_PARAMETER && parameterValue != TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER) {
            return false;
        }
        return true;
    }

    private static List<String> extractPersistedParameterValues(List<Target_UI_Controller__mdt> targetUiConfigs) {
        Set<String> parameterValues = new Set<String>();
        if (targetUiConfigs == null) {
            return new List<String>();
        }
        for (Target_UI_Controller__mdt config : targetUiConfigs) {
            if (config == null || config.Source_Type__c != 'Parameter' || !isPersistableCreationConfig(config)) {
                continue;
            }
            String parameterValue = normalizeTargetParameterLabel(
                String.isBlank(config.Source_Value__c) ? config.Parameter_Driver__c : config.Source_Value__c
            );
            if (config.Formula_Key__c == 'totalManpower') {
                parameterValues.add(TOTAL_MANPOWER_PARAMETER);
                parameterValue = TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER;
            }
            if (isApprovedTargetFamily(parameterValue)) {
                parameterValues.add(APPROVED_TARGET_PARAMETER);
                parameterValues.add(LEGACY_APPROVED_TARGET_PARAMETER);
                parameterValues.add(LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER);
            }
            if (isBaseHeadcountFamily(parameterValue)) {
                parameterValues.add(BASE_HEADCOUNT_PARAMETER);
                parameterValues.add(BASE_HEADCOUNT_NON_SUPP_PARAMETER);
            }
            if (String.isNotBlank(parameterValue)) {
                parameterValues.add(parameterValue);
            }
        }
        return new List<String>(parameterValues);
    }

    private static Boolean isPersistableCreationConfig(Target_UI_Controller__mdt config) {
        if (config == null) {
            return false;
        }
        String valueType = String.isBlank(config.Value_Type__c) ? '' : config.Value_Type__c.trim().toLowerCase();
        return valueType != 'text';
    }

    private static List<Target_UI_Controller__mdt> loadActiveTargetUiConfigs(String sector) {
        Set<String> sectorFilters = getSectorFilters(sector);
        return [
            SELECT DeveloperName, Sector__c, Section_Name__c, Category__c, Source_Section__c, Parameter_Driver__c, Classification__c,
                   Source_Type__c, UI_Line_Type__c, UI_Sequence__c, Internal_Key__c, Source_Value__c, Value_Type__c,
                   Formula_Key__c, Is_Editable__c, Is_Active__c
            FROM Target_UI_Controller__mdt
            WHERE Is_Active__c = true
            AND Sector__c IN :sectorFilters
            ORDER BY UI_Sequence__c ASC, DeveloperName ASC
        ];
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

    private static String buildUiSeedKey(Target_UI_Controller__mdt config) {
        return String.join(new List<String>{
            String.isBlank(config.Source_Type__c) ? '' : config.Source_Type__c.trim().toLowerCase(),
            String.isBlank(config.Source_Value__c) ? String.valueOf(config.Parameter_Driver__c).trim().toLowerCase() : config.Source_Value__c.trim().toLowerCase(),
            String.isBlank(config.Source_Section__c) ? '' : config.Source_Section__c.trim().toLowerCase(),
            String.isBlank(config.Classification__c) ? '' : normalizeClassification(config.Classification__c).toLowerCase()
        }, '|');
    }

    private static List<String> getTargetMonthParametersForSector(String sector) {
        List<String> parameters = new List<String>();
        parameters.addAll(SHARED_TARGET_MONTH_PARAMETERS);

        String sectorKey = normalizeTargetSectorKey(sector);
        if (sectorKey == GPS_SECTOR_KEY) {
            parameters.addAll(GPS_TARGET_MONTH_PARAMETERS);
        } else if (sectorKey == STAMPING_SECTOR_KEY) {
            parameters.addAll(STAMPING_TARGET_MONTH_PARAMETERS);
        }

        return parameters;
    }

    private static GWB_Month__c getPublishedTargetMonthOrFallback(
        Map<String, GWB_Month__c> publishedMonthsByParameter,
        String parameter,
        String classification,
        String formulaKey
    ) {
        for (String candidateParameter : getPublishedSourceParameterCandidates(parameter, formulaKey)) {
            GWB_Month__c sourceRow = publishedMonthsByParameter.get(buildPublishedMonthKey(candidateParameter, classification));
            if (sourceRow != null) {
                return sourceRow;
            }
        }
        if (classification != null) {
            for (String candidateParameter : getPublishedSourceParameterCandidates(parameter, formulaKey)) {
                GWB_Month__c sourceRow = publishedMonthsByParameter.get(buildPublishedMonthKey(candidateParameter, null));
                if (sourceRow != null) {
                    return sourceRow;
                }
            }
        }
        return buildFallbackPublishedTargetMonth(parameter, classification);
    }

    private static List<String> getPublishedSourceParameterCandidates(String parameter, String formulaKey) {
        List<String> candidates = new List<String>();
        if (String.isNotBlank(parameter)) {
            candidates.add(parameter);
        }
        if (isBaseHeadcountFamily(parameter)) {
            if (!candidates.contains(BASE_HEADCOUNT_PARAMETER)) {
                candidates.add(BASE_HEADCOUNT_PARAMETER);
            }
            if (!candidates.contains(BASE_HEADCOUNT_NON_SUPP_PARAMETER)) {
                candidates.add(BASE_HEADCOUNT_NON_SUPP_PARAMETER);
            }
        }
        if (isApprovedTargetFamily(parameter)) {
            addUniqueCandidate(candidates, APPROVED_TARGET_PARAMETER);
            addUniqueCandidate(candidates, LEGACY_APPROVED_TARGET_PARAMETER);
            addUniqueCandidate(candidates, LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER);
        }
        if (formulaKey == 'totalManpower' && !candidates.contains(TOTAL_MANPOWER_PARAMETER)) {
            candidates.add(TOTAL_MANPOWER_PARAMETER);
        }
        return candidates;
    }

    private static void addUniqueCandidate(List<String> candidates, String candidate) {
        if (String.isNotBlank(candidate) && !candidates.contains(candidate)) {
            candidates.add(candidate);
        }
    }

    private static GWB_Month__c buildFallbackPublishedTargetMonth(String parameter, String classification) {
        GWB_Month__c fallback = new GWB_Month__c();
        fallback.Parameter__c = parameter;
        fallback.Section__c = resolveSectionForParameter(parameter);
        fallback.Classification__c = classification;
        String valueType = resolveValueType(parameter);
        if (valueType == 'decimal') {
            fallback.Dec_Decimal__c = 0;
        } else if (valueType == 'percent') {
            fallback.Dec_Percent__c = 0;
        } else {
            fallback.Dec_Number__c = 0;
        }
        return fallback;
    }

    private static GWB_Month__c buildCopiedTargetMonthRow(
        GWB_Year__c targetRecord,
        GWB_Month__c sourceRow,
        String versionValue,
        String classification
    ) {
        String valueType = resolveValueType(sourceRow.Parameter__c);
        GWB_Month__c row = buildBaseTargetMonthRow(targetRecord, sourceRow.Section__c, sourceRow.Parameter__c, versionValue, classification);
        copyPrevDecFromPublishedDecember(row, sourceRow, valueType);
        if (!isApprovedTargetFamily(sourceRow.Parameter__c)) {
            copyPublishedDecemberAcrossYear(row, sourceRow, valueType);
        }
        return row;
    }

    private static void copyAdditionalStraightAdjustmentJustifications(Id sourceTargetId, Id targetId) {
        if (sourceTargetId == null || targetId == null) {
            return;
        }

        List<GWB_Budget_Comment__c> sourceComments = [
            SELECT Id, Cell_Key__c, Classification__c, Comment_Text__c, Month_Key__c, Row_Key__c,
                   Row_Label__c, Table_Name__c, Value_Snapshot__c, Original_Created_Date__c, CreatedDate
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c = :sourceTargetId
            AND Table_Name__c = :HOURS_JUSTIFICATION_TABLE
            AND Row_Key__c = :ADDITIONAL_ST_JUSTIFICATION_ROW_KEY
            AND Month_Key__c = 'dec'
            ORDER BY Original_Created_Date__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        if (sourceComments.isEmpty()) {
            return;
        }

        GWB_Budget_Comment__c sourceComment = sourceComments[0];
        List<GWB_Budget_Comment__c> commentsToInsert = new List<GWB_Budget_Comment__c>();
        for (String monthKey : MONTH_KEYS) {
            GWB_Budget_Comment__c clonedComment = sourceComment.clone(false, false, false, false);
            clonedComment.GWB_Year__c = targetId;
            clonedComment.Month_Key__c = monthKey;
            clonedComment.Cell_Key__c = buildCommentCellKey(HOURS_JUSTIFICATION_TABLE, ADDITIONAL_ST_JUSTIFICATION_ROW_KEY, monthKey);
            clonedComment.Original_Created_Date__c = sourceComment.Original_Created_Date__c != null
                ? sourceComment.Original_Created_Date__c
                : sourceComment.CreatedDate;
            commentsToInsert.add(clonedComment);
        }

        if (!commentsToInsert.isEmpty()) {
            insert commentsToInsert;
        }
    }

    private static String buildCommentCellKey(String tableName, String rowKey, String monthKey) {
        return String.join(new List<String>{
            String.isBlank(tableName) ? 'unknown' : tableName,
            String.isBlank(rowKey) ? 'unknown' : rowKey,
            String.isBlank(monthKey) ? 'unknown' : monthKey
        }, ':');
    }

    private static GWB_Month__c buildScheduledVolumeRow(
        GWB_Year__c targetRecord,
        GWB_Month__c sourceRow,
        Map<String, Decimal> monthlyVolumes,
        String versionValue,
        String classification
    ) {
        GWB_Month__c row = buildBaseTargetMonthRow(targetRecord, sourceRow.Section__c, sourceRow.Parameter__c, versionValue, classification);
        row.Prev_Dec_Number__c = getPublishedNumberBaseline(sourceRow);
        row.Jan_Number__c = monthlyVolumes.get('jan');
        row.Feb_Number__c = monthlyVolumes.get('feb');
        row.Mar_Number__c = monthlyVolumes.get('mar');
        row.Apr_Number__c = monthlyVolumes.get('apr');
        row.May_Number__c = monthlyVolumes.get('may');
        row.Jun_Number__c = monthlyVolumes.get('jun');
        row.Jul_Number__c = monthlyVolumes.get('jul');
        row.Aug_Number__c = monthlyVolumes.get('aug');
        row.Sep_Number__c = monthlyVolumes.get('sep');
        row.Oct_Number__c = monthlyVolumes.get('oct');
        row.Nov_Number__c = monthlyVolumes.get('nov');
        row.Dec_Number__c = monthlyVolumes.get('dec');
        return row;
    }

    private static GWB_Month__c buildBaseTargetMonthRow(
        GWB_Year__c targetRecord,
        String section,
        String parameter,
        String versionValue,
        String classification
    ) {
        return new GWB_Month__c(
            GWB_Year__c = targetRecord.Id,
            Plant__c = targetRecord.Plant__c,
            Sector__c = targetRecord.Sector__c,
            Year__c = targetRecord.Year__c,
            Data_Point_Value__c = versionValue,
            Section__c = section,
            Parameter__c = parameter,
            Classification__c = classification
        );
    }

    private static void copyPrevDecFromPublishedDecember(GWB_Month__c targetRow, GWB_Month__c sourceRow, String valueType) {
        if (valueType == 'decimal') {
            targetRow.Prev_Dec_Decimal__c = getPublishedDecimalBaseline(sourceRow);
        } else if (valueType == 'percent') {
            targetRow.Prev_Dec_Percent__c = getPublishedPercentBaseline(sourceRow);
        } else {
            targetRow.Prev_Dec_Number__c = getPublishedNumberBaseline(sourceRow);
        }
    }

    private static void copyPublishedDecemberAcrossYear(GWB_Month__c targetRow, GWB_Month__c sourceRow, String valueType) {
        if (valueType == 'decimal') {
            Decimal baselineValue = getPublishedDecimalBaseline(sourceRow);
            targetRow.Jan_Decimal__c = baselineValue;
            targetRow.Feb_Decimal__c = baselineValue;
            targetRow.Mar_Decimal__c = baselineValue;
            targetRow.Apr_Decimal__c = baselineValue;
            targetRow.May_Decimal__c = baselineValue;
            targetRow.Jun_Decimal__c = baselineValue;
            targetRow.Jul_Decimal__c = baselineValue;
            targetRow.Aug_Decimal__c = baselineValue;
            targetRow.Sep_Decimal__c = baselineValue;
            targetRow.Oct_Decimal__c = baselineValue;
            targetRow.Nov_Decimal__c = baselineValue;
            targetRow.Dec_Decimal__c = baselineValue;
        } else if (valueType == 'percent') {
            Decimal baselineValue = getPublishedPercentBaseline(sourceRow);
            targetRow.Jan_Percent__c = baselineValue;
            targetRow.Feb_Percent__c = baselineValue;
            targetRow.Mar_Percent__c = baselineValue;
            targetRow.Apr_Percent__c = baselineValue;
            targetRow.May_Percent__c = baselineValue;
            targetRow.Jun_Percent__c = baselineValue;
            targetRow.Jul_Percent__c = baselineValue;
            targetRow.Aug_Percent__c = baselineValue;
            targetRow.Sep_Percent__c = baselineValue;
            targetRow.Oct_Percent__c = baselineValue;
            targetRow.Nov_Percent__c = baselineValue;
            targetRow.Dec_Percent__c = baselineValue;
        } else {
            Decimal baselineValue = getPublishedNumberBaseline(sourceRow);
            targetRow.Jan_Number__c = baselineValue;
            targetRow.Feb_Number__c = baselineValue;
            targetRow.Mar_Number__c = baselineValue;
            targetRow.Apr_Number__c = baselineValue;
            targetRow.May_Number__c = baselineValue;
            targetRow.Jun_Number__c = baselineValue;
            targetRow.Jul_Number__c = baselineValue;
            targetRow.Aug_Number__c = baselineValue;
            targetRow.Sep_Number__c = baselineValue;
            targetRow.Oct_Number__c = baselineValue;
            targetRow.Nov_Number__c = baselineValue;
            targetRow.Dec_Number__c = baselineValue;
        }
    }

    // Some published targets only retain the carried baseline in Prev_Dec_*.
    // Fall back to that value when Dec_* is blank so the next draft still seeds correctly.
    private static Decimal getPublishedNumberBaseline(GWB_Month__c sourceRow) {
        return sourceRow.Dec_Number__c != null ? sourceRow.Dec_Number__c : sourceRow.Prev_Dec_Number__c;
    }

    private static Decimal getPublishedDecimalBaseline(GWB_Month__c sourceRow) {
        return sourceRow.Dec_Decimal__c != null ? sourceRow.Dec_Decimal__c : sourceRow.Prev_Dec_Decimal__c;
    }

    private static Decimal getPublishedPercentBaseline(GWB_Month__c sourceRow) {
        return sourceRow.Dec_Percent__c != null ? sourceRow.Dec_Percent__c : sourceRow.Prev_Dec_Percent__c;
    }

    private static String resolveValueType(String parameter) {
        parameter = normalizeTargetParameterLabel(parameter);
        if (parameter == 'Net/Net JPH' ||
            parameter == 'Paid Hours Per CREW' ||
            parameter == 'Available Working Days/Month' ||
            parameter == 'Production Working Days/Month' ||
            parameter == 'HARBOUR STROKES HPU' ||
            parameter == 'SOT from line time' ||
            parameter == 'Final Assembly Line JPH' ||
            parameter == 'SOT days (Weekends)' ||
            parameter == 'EQ SOT Days') {
            return 'decimal';
        }
        if (parameter == 'Absenteeism %' ||
            parameter == COMBINED_ABSENCE_PARAMETER ||
            parameter == 'Equivalent SOT %' ||
            parameter == 'SOT percent from weekend days' ||
            parameter == 'NSOT %') {
            return 'percent';
        }
        return 'number';
    }

    private static String resolvePersistedParameterValue(String parameter) {
        parameter = normalizeTargetParameterLabel(parameter);
        if (isApprovedTargetFamily(parameter)) {
            return APPROVED_TARGET_PARAMETER;
        }
        return parameter;
    }

    private static String resolveSectionForParameter(String parameter) {
        parameter = normalizeTargetParameterLabel(parameter);
        if (isBaseHeadcountFamily(parameter) ||
            isApprovedTargetFamily(parameter) ||
            parameter == TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER ||
            parameter == TOTAL_MANPOWER_PARAMETER ||
            parameter == 'Absenteeism %' ||
            parameter == 'NSOT %' ||
            parameter == ADDITIONAL_ST_ADJUSTMENT_PARAMETER) {
            return MANPOWER_SECTION;
        }
        if (parameter == ADDITIONAL_ST_HOURS_PARAMETER ||
            parameter == COMBINED_ABSENCE_PARAMETER ||
            parameter == 'Scheduled Overtime Hours' ||
            parameter == ST_HOURS_INCLUDE_ADDITIONAL_ST_PARAMETER ||
            parameter == NSOT_HOURS_PARAMETER ||
            parameter == 'Total Hours' ||
            parameter == 'AHPU Monthly' ||
            parameter == 'AHPU YTD' ||
            parameter == 'WHPU Monthly' ||
            parameter == 'Additional OT Time Hours (Manual)') {
            return SECTION_HOURS;
        }
        return SCHEDULED_VOLUME_SECTION;
    }

    private static Map<String, Decimal> initializeMonthlyVolumeMap() {
        return new Map<String, Decimal>{
            'jan' => 0,
            'feb' => 0,
            'mar' => 0,
            'apr' => 0,
            'may' => 0,
            'jun' => 0,
            'jul' => 0,
            'aug' => 0,
            'sep' => 0,
            'oct' => 0,
            'nov' => 0,
            'dec' => 0
        };
    }

    private static String normalizeMonthKey(String monthValue) {
        if (String.isBlank(monthValue)) {
            return null;
        }

        String normalized = monthValue.trim().toLowerCase();
        if (normalized.length() >= 3) {
            normalized = normalized.substring(0, 3);
        }

        return initializeMonthlyVolumeMap().containsKey(normalized) ? normalized : null;
    }

    private static VacationCoverageSeed loadVacationCoverageSeed(Id plantId, String sector, String yearValue) {
        if (plantId == null || String.isBlank(yearValue) || String.valueOf(sector).trim() != ASSEMBLY_SECTOR) {
            return null;
        }

        List<GWB_Vacation_Coverage__c> records = [
            SELECT Vacation_Percent__c, Entry_Month_Year__c, Exit_Month_Year__c
            FROM GWB_Vacation_Coverage__c
            WHERE Plant__c = :plantId
            AND Year__c = :yearValue
            AND Sector__c = :sector
            AND Classification__c = 'OTS'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return null;
        }

        String entryMonthKey = normalizeMonthKeyFromText(records[0].Entry_Month_Year__c);
        String exitMonthKey = normalizeMonthKeyFromText(records[0].Exit_Month_Year__c);
        if (String.isBlank(entryMonthKey) || String.isBlank(exitMonthKey) || records[0].Vacation_Percent__c == null) {
            return null;
        }

        VacationCoverageSeed seed = new VacationCoverageSeed();
        seed.vacationPercent = records[0].Vacation_Percent__c;
        seed.entryMonthKey = entryMonthKey;
        seed.exitMonthKey = exitMonthKey;
        return seed;
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

    private static Set<String> extractVehicleBrands(String vehicleBrandValue) {
        Set<String> vehicleBrands = new Set<String>();
        if (String.isBlank(vehicleBrandValue)) {
            return vehicleBrands;
        }

        for (String brand : vehicleBrandValue.split(';')) {
            String normalizedBrand = brand == null ? null : brand.trim();
            if (String.isNotBlank(normalizedBrand)) {
                vehicleBrands.add(normalizedBrand);
            }
        }

        return vehicleBrands;
    }

    private static Plant__c getPolymersAssemblyPlant(String authSiteName) {
        if (String.isBlank(authSiteName)) {
            return null;
        }

        List<Plant__c> assemblyPlants = [
            SELECT Id, Vehicle_Brand__c
            FROM Plant__c
            WHERE Auth_Site_Name__c = :authSiteName
            AND Auth_Sector__c = 'Assembly'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return assemblyPlants.isEmpty() ? null : assemblyPlants[0];
    }

    private static String buildScheduledVolumeKey(Id plantId, String sector, String yearValue) {
        return String.valueOf(plantId) + '|' + String.valueOf(sector) + '|' + String.valueOf(yearValue);
    }

    private static String buildPublishedMonthKey(String parameter, String classification) {
        return String.valueOf(normalizeTargetParameterLabel(parameter)) + '|' + normalizeClassification(classification);
    }

    private static String buildPublishedDriverKey(String driver, String classification) {
        return String.valueOf(normalizeDriverValue(driver)) + '|' + normalizeClassification(classification);
    }

    private static String resolveSector(Plant_Sector__c plantSector) {
        if (plantSector == null) {
            return '';
        }
        if (String.isNotBlank(plantSector.Auth_Sector__c)) {
            return plantSector.Auth_Sector__c;
        }
        if (plantSector.Plant__r != null && plantSector.Plant__r.Auth_Sector__c != null) {
            return String.valueOf(plantSector.Plant__r.Auth_Sector__c);
        }
        if (plantSector.Plant__c == null) {
            return '';
        }

        List<Plant__c> plants = [
            SELECT Auth_Sector__c
            FROM Plant__c
            WHERE Id = :plantSector.Plant__c
            LIMIT 1
        ];
        return plants.isEmpty() || plants[0].Auth_Sector__c == null
            ? ''
            : String.valueOf(plants[0].Auth_Sector__c);
    }

    private static String normalizeTargetSectorKey(String sector) {
        String normalized = String.isBlank(sector) ? '' : sector.trim().toLowerCase();
        if (normalized.contains('gps')) {
            return GPS_SECTOR_KEY;
        }
        if (normalized.contains('stamp') || normalized.contains('press')) {
            return STAMPING_SECTOR_KEY;
        }
        return 'assembly';
    }

    private static String normalizeClassification(String classification) {
        if (String.isBlank(classification)) {
            return '';
        }
        if (classification == 'Shared' || classification == 'shared' ||
            classification == 'Calculated' || classification == 'calculated' ||
            classification == 'Mschedule' || classification == 'mschedule') {
            return '';
        }
        if (classification == 'OST') {
            return 'OTS';
        }
        if (classification == 'OTS') {
            return 'OTS';
        }
        if (classification == 'SK') {
            return 'Skilled';
        }
        if (classification == 'SAL') {
            return 'Salaried';
        }
        if (classification == 'Salary' || classification == 'salary') {
            return 'Salaried';
        }
        if (classification == 'Total' || classification == 'total') {
            return 'Total';
        }
        return classification;
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

    private static String normalizeValueType(String configuredValueType, String parameterValue) {
        String normalized = String.isBlank(configuredValueType) ? null : configuredValueType.trim().toLowerCase();
        if (normalized == 'number' || normalized == 'decimal' || normalized == 'percent' || normalized == 'percentage' || normalized == 'text') {
            if (normalized == 'percentage') {
                return 'percent';
            }
            return normalized;
        }
        return resolveValueType(parameterValue);
    }

    private static String normalizeDriverValue(String driverValue) {
        if (driverValue == 'Vac. Replacement') {
            return 'Vacation Replacement';
        }
        if (driverValue == 'Others/Excess') {
            return 'Other/Excess';
        }
        return driverValue;
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
        if (normalized == APPROVED_TARGET_PARAMETER ||
            normalized == LEGACY_APPROVED_TARGET_PARAMETER ||
            normalized == LEGACY_ADVANCED_TARGET_CHANGES_PARAMETER) {
            return APPROVED_TARGET_PARAMETER;
        }
        return normalized;
    }

    private static String resolveStoredCategory(Target_UI_Controller__mdt config) {
        if (config == null) {
            return null;
        }
        if (String.isNotBlank(config.Category__c)) {
            return config.Category__c;
        }
        String sourceSection = normalizeStoredSection(config.Source_Section__c);
        if (sourceSection == SCHEDULED_VOLUME_SECTION) {
            return CATEGORY_OP_PLAN;
        }
        if (sourceSection == MANPOWER_SECTION) {
            return CATEGORY_HEADCOUNT;
        }

        String combined = String.join(
            new List<String>{
                String.valueOf(config.Category__c),
                String.valueOf(config.Section_Name__c),
                String.valueOf(config.Parameter_Driver__c),
                String.valueOf(config.Formula_Key__c)
            },
            ' '
        ).toLowerCase();
        if (combined.contains('hour')) {
            return CATEGORY_HOURS;
        }
        if (config.Formula_Key__c == 'totalManpower' ||
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

    private static String resolveStoredSection(Target_UI_Controller__mdt config) {
        if (config == null) {
            return null;
        }
        if (String.isNotBlank(config.Source_Section__c)) {
            return normalizeStoredSection(config.Source_Section__c);
        }
        if (config.Source_Type__c == 'Parameter') {
            String parameterValue = normalizeTargetParameterLabel(
                String.isBlank(config.Source_Value__c) ? config.Parameter_Driver__c : config.Source_Value__c
            );
            if (config.Formula_Key__c == 'totalManpower') {
                parameterValue = TOTAL_MANPOWER_INCLUDE_TARGET_CHANGES_PARAMETER;
            }
            return resolveSectionForParameter(resolvePersistedParameterValue(parameterValue));
        }
        String storedCategory = resolveStoredCategory(config);
        if (storedCategory == CATEGORY_HEADCOUNT) {
            return MANPOWER_SECTION;
        }
        if (storedCategory == CATEGORY_OP_PLAN) {
            return SCHEDULED_VOLUME_SECTION;
        }
        return SECTION_HOURS;
    }

    private static String normalizeStoredSection(String section) {
        if (String.isBlank(section)) {
            return null;
        }
        String normalizedSection = section.trim().toLowerCase();
        if (normalizedSection == SCHEDULED_VOLUME_SECTION.toLowerCase() ||
            normalizedSection == LEGACY_SCHEDULED_VOLUME_SECTION.toLowerCase()) {
            return SCHEDULED_VOLUME_SECTION;
        }
        if (normalizedSection == MANPOWER_SECTION.toLowerCase() ||
            normalizedSection == LEGACY_MANPOWER_SECTION.toLowerCase()) {
            return MANPOWER_SECTION;
        }
        return SECTION_HOURS;
    }

    private static String resolveStoredValueType(Target_UI_Controller__mdt config) {
        if (config == null) {
            return VALUE_TYPE_VALUE;
        }
        if (config.Formula_Key__c == 'totalManpower') {
            return isTotalClassification(config.Classification__c) ? VALUE_TYPE_TOTAL : VALUE_TYPE_VALUE;
        }
        if (config.UI_Line_Type__c == 'Total') {
            return VALUE_TYPE_TOTAL;
        }
        return VALUE_TYPE_VALUE;
    }

    private static Boolean isTotalClassification(String classification) {
        return String.isBlank(classification) || normalizeClassification(classification) == 'Total';
    }

    private static Id getTargetRecordTypeId() {
        if (cachedTargetRecordTypeId == null) {
            Schema.RecordTypeInfo recordTypeInfo = GWB_Year__c.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get(TARGET_RECORD_TYPE);
            if (recordTypeInfo == null) {
                throw new DraftTargetProcessingException('The Target record type is not configured for GWB Year.');
            }
            cachedTargetRecordTypeId = recordTypeInfo.getRecordTypeId();
        }
        return cachedTargetRecordTypeId;
    }

    private static String normalizeVersion(String versionValue) {
        if (String.isBlank(versionValue)) {
            return '';
        }
        return versionValue.replace('%2B', '+');
    }

    private static String buildGwbVersionValue(String versionValue, String targetYear) {
        return String.isBlank(versionValue) || String.isBlank(targetYear)
            ? versionValue
            : targetYear + ' ' + versionValue;
    }

    private static String buildSuccessMessage(Plant_Sector__c plantSector, TargetCreationOutcome outcome) {
        String plantName = outcome != null && String.isNotBlank(outcome.plantName)
            ? outcome.plantName
            : (plantSector != null && plantSector.Plant__r != null ? plantSector.Plant__r.Name : 'Unknown Plant');
        String sector = outcome != null && String.isNotBlank(outcome.sector)
            ? outcome.sector
            : resolveSector(plantSector);
        return plantName + ' / ' + sector +
            ': created target ' + safeValue(String.valueOf(outcome != null ? outcome.targetId : null)) +
            ' for year ' + safeValue(outcome != null ? outcome.targetYear : null) +
            ' using previous locked target ' + safeValue(String.valueOf(outcome != null ? outcome.previousLockedTargetId : null)) +
            '; metadata rows=' + String.valueOf(outcome != null ? outcome.uiConfigCount : 0) +
            ', month rows=' + String.valueOf(outcome != null ? outcome.createdMonthRowCount : 0) +
            ', scheduled volume months=' + String.valueOf(outcome != null ? outcome.populatedScheduledVolumeMonths : 0);
    }

    private static String buildFailureMessage(Plant_Sector__c plantSector, Exception e) {
        String plantName = plantSector != null && plantSector.Plant__r != null ? plantSector.Plant__r.Name : 'Unknown Plant';
        String sector = resolveSector(plantSector);
        return plantName + ' / ' + sector + ': ' + e.getMessage();
    }

    private static String safeValue(String value) {
        return String.isBlank(value) ? 'none' : value;
    }

    private static Integer countPopulatedMonths(Map<String, Decimal> monthlyVolumes) {
        Integer count = 0;
        if (monthlyVolumes == null) {
            return count;
        }
        for (String monthKey : MONTH_KEYS) {
            Decimal monthValue = monthlyVolumes.get(monthKey);
            if (monthValue != null && monthValue != 0) {
                count++;
            }
        }
        return count;
    }

    private static void logInfo(String message) {
        System.debug(LoggingLevel.INFO, 'DraftTargetCreationService | ' + message);
    }

    private static void logWarn(String message) {
        System.debug(LoggingLevel.WARN, 'DraftTargetCreationService | ' + message);
    }
}