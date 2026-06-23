public with sharing class GwbBudgetDraftSeedService {
    private static final List<String> MONTH_KEYS = new List<String>{
        'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
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

    private static final Map<String, String> DRIVER_MONTH_FIELDS = new Map<String, String>{
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

    private class SharedSeedDef {
        String section;
        String parameter;
        String classification;
        String valueType;
        Boolean populateFromPreviousDec;
        Boolean populateFromScheduledVolume;

        SharedSeedDef(String section, String parameter, String classification, String valueType, Boolean populateFromPreviousDec, Boolean populateFromScheduledVolume) {
            this.section = section;
            this.parameter = parameter;
            this.classification = classification;
            this.valueType = valueType;
            this.populateFromPreviousDec = populateFromPreviousDec;
            this.populateFromScheduledVolume = populateFromScheduledVolume;
        }
    }

    private class DriverSeedDef {
        String objectApiName;
        String driver;
        String classification;

        DriverSeedDef(String objectApiName, String driver, String classification) {
            this.objectApiName = objectApiName;
            this.driver = driver;
            this.classification = classification;
        }
    }

    public static void seedDraft(Id draftBudgetId, Id previousYearGwbId, Id plantId, String sector, String year, String version) {
        if (draftBudgetId == null || previousYearGwbId == null || plantId == null || String.isBlank(sector) || String.isBlank(year) || String.isBlank(version)) {
            throw new AuraHandledException('Unable to seed the draft budget because the required context is incomplete.');
        }

        if (hasExistingSeedData(draftBudgetId)) {
            return;
        }

        Map<String, GWB_Month__c> previousSharedByKey = new Map<String, GWB_Month__c>();
        for (GWB_Month__c previousShared : [
            SELECT Id, Section__c, Parameter__c, Classification__c,
                   Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c,
                   Prev_Dec_Decimal__c, Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c, Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                   Prev_Dec_Percent__c, Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Apr_Percent__c, May_Percent__c, Jun_Percent__c, Jul_Percent__c, Aug_Percent__c, Sep_Percent__c, Oct_Percent__c, Nov_Percent__c, Dec_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :previousYearGwbId
        ]) {
            previousSharedByKey.put(buildSharedKey(previousShared.Parameter__c, previousShared.Classification__c), previousShared);
        }

        Map<String, Decimal> scheduledVolumeByMonth = loadScheduledVolumeByMonth(plantId, sector, year, version);
        Map<String, Map<String, Decimal>> previousDriverValuesBySeedKey = loadPreviousDriverValues(previousYearGwbId);

        List<GWB_Month__c> sharedRowsToInsert = new List<GWB_Month__c>();
        for (SharedSeedDef definition : buildSharedSeedDefs(sector)) {
            GWB_Month__c draftRow = new GWB_Month__c(
                GWB_Year__c = draftBudgetId,
                Section__c = definition.section,
                Parameter__c = definition.parameter,
                Classification__c = definition.classification
            );

            GWB_Month__c previousRow = previousSharedByKey.get(buildSharedKey(definition.parameter, definition.classification));
            Decimal previousDecValue = getPreviousDecemberValue(previousRow, definition.valueType);
            assignSharedValue(draftRow, definition.valueType, 'prevDec', previousDecValue);

            if (definition.populateFromScheduledVolume) {
                for (String monthKey : MONTH_KEYS) {
                    assignSharedValue(draftRow, definition.valueType, monthKey, scheduledVolumeByMonth.get(monthKey));
                }
            } else if (definition.populateFromPreviousDec) {
                for (String monthKey : MONTH_KEYS) {
                    assignSharedValue(draftRow, definition.valueType, monthKey, previousDecValue);
                }
            }

            sharedRowsToInsert.add(draftRow);
        }

        Map<String, List<SObject>> driverRowsByObject = new Map<String, List<SObject>>();
        for (DriverSeedDef definition : buildDriverSeedDefs()) {
            SObject driverRow = Schema.getGlobalDescribe().get(definition.objectApiName).newSObject();
            driverRow.put('GWB_Master__c', draftBudgetId);
            driverRow.put('Driver__c', definition.driver);
            driverRow.put('Classification__c', definition.classification);
            driverRow.put('Plant__c', plantId);
            driverRow.put('Sector__c', sector);
            driverRow.put('Year__c', year);
            driverRow.put('Data_Point_Value__c', version);

            for (String monthKey : MONTH_KEYS) {
                Decimal seededValue = shouldSeedAssemblyVacationCoverage(sector, definition)
                    ? getSeededDriverValue(previousDriverValuesBySeedKey, definition, monthKey)
                    : 0;
                driverRow.put(DRIVER_MONTH_FIELDS.get(monthKey), seededValue);
            }
            if (!driverRowsByObject.containsKey(definition.objectApiName)) {
                driverRowsByObject.put(definition.objectApiName, new List<SObject>());
            }
            driverRowsByObject.get(definition.objectApiName).add(driverRow);
        }

        insert sharedRowsToInsert;
        for (List<SObject> driverBatch : driverRowsByObject.values()) {
            if (!driverBatch.isEmpty()) {
                insert driverBatch;
            }
        }
    }

    private static Boolean hasExistingSeedData(Id draftBudgetId) {
        return [
            SELECT COUNT()
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudgetId
        ] > 0;
    }

    private static List<SharedSeedDef> buildSharedSeedDefs(String sector) {
        List<SharedSeedDef> definitions = new List<SharedSeedDef>{
            new SharedSeedDef('Scheduled_Volume', 'Crews', null, 'number', true, false),
            new SharedSeedDef('Scheduled_Volume', 'Shifts', null, 'number', true, false),
            new SharedSeedDef('Scheduled_Volume', 'Scheduled Volume', null, 'number', false, true),
            new SharedSeedDef('Scheduled_Volume', 'Paid Hours Per CREW', null, 'decimal', true, false),
            new SharedSeedDef('Scheduled_Volume', 'Available Working Days/Month', null, 'decimal', true, false),
            new SharedSeedDef('Scheduled_Volume', 'Production Working Days/Month', null, 'decimal', true, false),
            new SharedSeedDef('Manpower', 'Base Headcount', 'OTS', 'number', true, false),
            new SharedSeedDef('Manpower', 'Base Headcount', 'Skilled', 'number', true, false),
            new SharedSeedDef('Manpower', 'Base Headcount', 'Salaried', 'number', true, false),
            new SharedSeedDef('Manpower', 'Approved Target', 'OTS', 'number', false, false),
            new SharedSeedDef('Manpower', 'Approved Target', 'Skilled', 'number', false, false),
            new SharedSeedDef('Manpower', 'Approved Target', 'Salaried', 'number', false, false),
            new SharedSeedDef('Manpower', 'Additional Straight Time Hours Adjustment', 'OTS', 'number', true, false),
            new SharedSeedDef('Manpower', 'Additional Straight Time Hours Adjustment', 'Skilled', 'number', true, false),
            new SharedSeedDef('Manpower', 'Additional Straight Time Hours Adjustment', 'Salaried', 'number', true, false),
            new SharedSeedDef('Manpower', 'Absenteeism %', 'OTS', 'percent', true, false),
            new SharedSeedDef('Manpower', 'Absenteeism %', 'Skilled', 'percent', true, false),
            new SharedSeedDef('Manpower', 'Absenteeism %', 'Salaried', 'percent', true, false),
            new SharedSeedDef('Manpower', 'NSOT %', 'OTS', 'percent', true, false),
            new SharedSeedDef('Manpower', 'NSOT %', 'Skilled', 'percent', true, false),
            new SharedSeedDef('Manpower', 'NSOT %', 'Salaried', 'percent', true, false)
        };

        String normalizedSector = normalizeSector(sector);
        if (normalizedSector == 'gps') {
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Final Assembly Line JPH', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Daily Op Plan Volume', null, 'number', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'SOT days (Weekends)', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'EQ SOT Days (Additional Weekday hours)', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Total SOT Days', null, 'decimal', true, false));
            return definitions;
        }

        if (normalizedSector == 'stamping') {
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Equivalent Units Volume', null, 'number', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Net/Net JPH', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Daily Op Plan Volume', null, 'number', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'HARBOUR STROKES HPU', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Scheduled Volume Pieces', null, 'number', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Scheduled Volume Strokes', null, 'number', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'Equivalent SOT %', null, 'percent', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'SOT percent from weekend days', null, 'percent', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'SOT from line time', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'SOT equivalent days total', null, 'decimal', true, false));
            definitions.add(new SharedSeedDef('Scheduled_Volume', 'EQ SOT Days', null, 'decimal', true, false));
            return definitions;
        }

        definitions.add(new SharedSeedDef('Scheduled_Volume', 'Net/Net JPH', null, 'decimal', true, false));
        definitions.add(new SharedSeedDef('Scheduled_Volume', 'EQ SOT Days', null, 'decimal', true, false));
        return definitions;
    }

    private static String normalizeSector(String sector) {
        String normalized = String.isBlank(sector) ? '' : sector.trim().toLowerCase();
        if (normalized.contains('press')) {
            return 'stamping';
        }
        return normalized;
    }

    private static List<DriverSeedDef> buildDriverSeedDefs() {
        List<DriverSeedDef> seedDefs = new List<DriverSeedDef>();
        List<String> drivers = new List<String>{
            'Productivity',
            'ARC',
            'LMS',
            'Op Plan',
            'Vacation Replacement',
            'Content',
            'Sourcing',
            'Mfg Opt',
            'Launch',
            'Containment',
            'Other/Excess'
        };

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<DriverSeedDef> supportedObjectDefinitions = new List<DriverSeedDef>{
            new DriverSeedDef('GWB_Month_OTS__c', null, 'OTS'),
            new DriverSeedDef('GWB_Month_Skilled__c', null, 'SK'),
            new DriverSeedDef('GWB_Month_Salaried__c', null, 'SAL')
        };

        for (String driver : drivers) {
            for (DriverSeedDef supportedDefinition : supportedObjectDefinitions) {
                if (!globalDescribe.containsKey(supportedDefinition.objectApiName)) {
                    continue;
                }
                seedDefs.add(new DriverSeedDef(
                    supportedDefinition.objectApiName,
                    driver,
                    supportedDefinition.classification
                ));
            }
        }
        return seedDefs;
    }

    private static String buildSharedKey(String parameter, String classification) {
        return String.valueOf(parameter) + '|' + String.valueOf(classification);
    }

    private static String buildDriverSeedKey(String objectApiName, String driver, String classification) {
        return String.join(new List<String>{
            String.valueOf(objectApiName),
            String.valueOf(driver),
            normalizeSeedClassification(classification)
        }, '|');
    }

    private static Map<String, Map<String, Decimal>> loadPreviousDriverValues(Id previousYearGwbId) {
        Map<String, Map<String, Decimal>> valuesBySeedKey = new Map<String, Map<String, Decimal>>();
        if (previousYearGwbId == null) {
            return valuesBySeedKey;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String objectApiName : new List<String>{ 'GWB_Month_OTS__c', 'GWB_Month_Skilled__c', 'GWB_Month_Salaried__c' }) {
            if (!globalDescribe.containsKey(objectApiName)) {
                continue;
            }
            String soql =
                'SELECT Driver__c, Classification__c,' +
                ' Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c,' +
                ' Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c' +
                ' FROM ' + objectApiName +
                ' WHERE GWB_Master__c = :previousYearGwbId';
            for (SObject previousRow : Database.query(soql)) {
                String classification = normalizeSeedClassification((String) previousRow.get('Classification__c'));
                valuesBySeedKey.put(
                    buildDriverSeedKey(objectApiName, (String) previousRow.get('Driver__c'), classification),
                    extractDriverMonthValues(previousRow)
                );
            }
        }

        return valuesBySeedKey;
    }

    private static Map<String, Decimal> extractDriverMonthValues(SObject row) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (String monthKey : MONTH_KEYS) {
            String fieldName = DRIVER_MONTH_FIELDS.get(monthKey);
            values.put(monthKey, fieldName == null ? 0 : (Decimal) row.get(fieldName));
        }
        return values;
    }

    private static Boolean shouldSeedAssemblyVacationCoverage(String sector, DriverSeedDef definition) {
        return sector == 'Assembly' && definition != null && definition.driver == 'Vacation Replacement';
    }

    private static Decimal getSeededDriverValue(Map<String, Map<String, Decimal>> previousDriverValuesBySeedKey, DriverSeedDef definition, String monthKey) {
        if (previousDriverValuesBySeedKey == null || definition == null) {
            return 0;
        }

        Map<String, Decimal> values = previousDriverValuesBySeedKey.get(
            buildDriverSeedKey(definition.objectApiName, definition.driver, definition.classification)
        );
        return values == null ? 0 : (values.containsKey(monthKey) ? values.get(monthKey) : 0);
    }

    private static String normalizeSeedClassification(String value) {
        if (value == 'Skilled') {
            return 'Skilled';
        }
        if (value == 'Salaried') {
            return 'Salaried';
        }
        if (value == 'SK') {
            return 'Skilled';
        }
        if (value == 'SAL') {
            return 'Salaried';
        }
        return 'OTS';
    }

    private static Decimal getPreviousDecemberValue(GWB_Month__c previousRow, String valueType) {
        if (previousRow == null) {
            return 0;
        }

        if (valueType == 'decimal') {
            return previousRow.Dec_Decimal__c == null ? 0 : previousRow.Dec_Decimal__c;
        }
        if (valueType == 'percent') {
            return previousRow.Dec_Percent__c == null ? 0 : previousRow.Dec_Percent__c;
        }
        return previousRow.Dec_Number__c == null ? 0 : previousRow.Dec_Number__c;
    }

    private static void assignSharedValue(GWB_Month__c row, String valueType, String monthKey, Decimal value) {
        Map<String, String> fieldMap = valueType == 'decimal'
            ? SHARED_DECIMAL_FIELDS
            : valueType == 'percent'
                ? SHARED_PERCENT_FIELDS
                : SHARED_NUMBER_FIELDS;

        String fieldName = fieldMap.get(monthKey);
        if (String.isNotBlank(fieldName)) {
            row.put(fieldName, value);
        }
    }

    private static Map<String, Decimal> loadScheduledVolumeByMonth(Id plantId, String sector, String year, String version) {
        Map<String, Decimal> totalsByMonth = new Map<String, Decimal>();
        for (String monthKey : MONTH_KEYS) {
            totalsByMonth.put(monthKey, 0);
        }

        for (AggregateResult result : [
            SELECT Month__c monthValue, SUM(Volume__c) totalVolume
            FROM Plant_Volume__c
            WHERE Plant__c = :plantId
            AND Sector__c = :sector
            AND Calendar_Year__c = :year
            AND Data_Point_Value__c = :version
            GROUP BY Month__c
        ]) {
            String normalizedMonth = normalizeMonthKey((String) result.get('monthValue'));
            if (normalizedMonth != null) {
                totalsByMonth.put(normalizedMonth, (Decimal) result.get('totalVolume'));
            }
        }

        return totalsByMonth;
    }

    private static String normalizeMonthKey(String monthValue) {
        if (String.isBlank(monthValue)) {
            return null;
        }

        String normalized = monthValue.trim().toLowerCase();
        if (normalized.length() >= 3) {
            normalized = normalized.substring(0, 3);
        }

        if (new Set<String>(MONTH_KEYS).contains(normalized)) {
            return normalized;
        }
        return null;
    }
}