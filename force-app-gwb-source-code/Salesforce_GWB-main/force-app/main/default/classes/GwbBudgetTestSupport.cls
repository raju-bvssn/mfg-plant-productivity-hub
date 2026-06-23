@IsTest
public class GwbBudgetTestSupport {
    public static final String VERSION = '01+11';
    private static final String MANPOWER_SECTION_LEGACY = 'Manpower';
    private static final String SCHEDULED_VOLUME_SECTION_LEGACY = 'Scheduled_Volume';

    public static Id getGwbYearRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    } 

    public static Plant__c createPlant(String name, String sector, String vehicleBrands) {
        Plant__c plantRecord = new Plant__c(
            Name = String.isBlank(name) ? 'Test Plant ' + System.now().getTime() : name,
            Auth_Region__c = normalizePicklistValue(Plant__c.Auth_Region__c, null),
            MVP__c = 'GWB'
        );
        if (!String.isBlank(sector)) {
            plantRecord.Auth_Sector__c = normalizePicklistValue(Plant__c.Auth_Sector__c, sector);
        }
        if (!String.isBlank(vehicleBrands)) {
            plantRecord.Vehicle_Brand__c = vehicleBrands;
        }
        insert plantRecord;
        return plantRecord;
    }

    public static Plant_Sector__c createPlantSector(Id plantId, String sector, String programCode, String functionalArea) {
        Plant_Sector__c plantSector = new Plant_Sector__c(
            Plant__c = plantId,
            Program_Code__c = programCode,
            Functional_Area__c = functionalArea
        );
        insert plantSector;
        return plantSector;
    }

    public static GWB_Year__c createTarget(
        Id plantId,
        Id plantSectorId,
        String sector,
        String year,
        String status,
        String version
    ) {
        GWB_Year__c targetRecord = new GWB_Year__c(
            Plant__c = plantId,
            Plant_Sector__c = plantSectorId,
            Sector__c = normalizePicklistValue(GWB_Year__c.Sector__c, sector),
            Year__c = year,
            Status__c = status,
            Version__c = String.isBlank(version) ? 'TargetVersion' : version,
            M_Schedule_Version__c = normalizePicklistValue(
                GWB_Year__c.M_Schedule_Version__c,
                String.isBlank(version) ? VERSION : version
            ),
            RecordTypeId = getGwbYearRecordTypeId('Target')
        );
        insert targetRecord;
        return targetRecord;
    }

    public static GWB_Year__c createBudget(
        Id plantId,
        Id plantSectorId,
        String sector,
        String year,
        String status,
        String version,
        Id previousYearBudgetId
    ) {
        GWB_Year__c budgetRecord = new GWB_Year__c(
            Plant__c = plantId,
            Plant_Sector__c = plantSectorId,
            Sector__c = normalizePicklistValue(GWB_Year__c.Sector__c, sector),
            Year__c = year,
            Status__c = status,
            Version__c = normalizePicklistValue(
                GWB_Year__c.M_Schedule_Version__c,
                String.isBlank(version) ? VERSION : version
            ),
            M_Schedule_Version__c = normalizePicklistValue(
                GWB_Year__c.M_Schedule_Version__c,
                String.isBlank(version) ? VERSION : version
            ),
            Previous_Year_GWB__c = previousYearBudgetId,
            RecordTypeId = getGwbYearRecordTypeId('Budget')
        );
        insert budgetRecord;
        return budgetRecord;
    }

    public static GWB_Month__c createSharedMonth(
        Id gwbYearId,
        Id plantId,
        String sector,
        String year,
        String version,
        String section,
        String parameter,
        String classification,
        String valueType,
        Decimal prevDec,
        Decimal jan,
        Decimal feb,
        Decimal dec
    ) {
        GWB_Month__c row = new GWB_Month__c(
            GWB_Year__c = gwbYearId,
            Plant__c = plantId,
            Sector__c = normalizePicklistValue(GWB_Month__c.Sector__c, sector),
            Year__c = year,
            Data_Point_Value__c = version,
            Section__c = normalizeMonthSection(section),
            Parameter__c = normalizeMonthParameter(parameter),
            Classification__c = normalizePicklistValue(GWB_Month__c.Classification__c, classification)
        );

        if (valueType == 'decimal') {
            row.Prev_Dec_Decimal__c = prevDec;
            row.Jan_Decimal__c = jan;
            row.Feb_Decimal__c = feb;
            row.Dec_Decimal__c = dec;
        } else if (valueType == 'percent') {
            row.Prev_Dec_Percent__c = prevDec;
            row.Jan_Percent__c = jan;
            row.Feb_Percent__c = feb;
            row.Dec_Percent__c = dec;
        } else {
            row.Prev_Dec_Number__c = prevDec;
            row.Jan_Number__c = jan;
            row.Feb_Number__c = feb;
            row.Dec_Number__c = dec;
        }

        insert row;
        return row;
    }

    public static GWB_Month__c createDriverMonth(
        Id gwbYearId,
        Id plantId,
        String sector,
        String year,
        String version,
        String driver,
        String classification,
        Decimal jan,
        Decimal feb,
        Decimal dec
    ) {
        GWB_Month__c row = new GWB_Month__c(
            GWB_Year__c = gwbYearId,
            Plant__c = plantId,
            Sector__c = normalizePicklistValue(GWB_Month__c.Sector__c, sector),
            Year__c = year,
            Data_Point_Value__c = version,
            Driver__c = driver,
            Classification__c = normalizePicklistValue(GWB_Month__c.Classification__c, classification),
            Jan_Number__c = jan,
            Feb_Number__c = feb,
            Dec_Number__c = dec
        );
        insert row;
        return row;
    }

    public static GWB_Budget_Comment__c createComment(
        Id gwbYearId,
        String tableName,
        String rowKey,
        String rowLabel,
        String monthKey,
        String classification,
        String commentText,
        String valueSnapshot
    ) {
        GWB_Budget_Comment__c commentRecord = new GWB_Budget_Comment__c(
            GWB_Year__c = gwbYearId,
            Table_Name__c = tableName,
            Row_Key__c = rowKey,
            Row_Label__c = rowLabel,
            Month_Key__c = monthKey,
            Classification__c = classification,
            Comment_Text__c = commentText,
            Value_Snapshot__c = valueSnapshot,
            Cell_Key__c = String.join(new List<String>{
                String.isBlank(tableName) ? 'unknown' : tableName,
                String.isBlank(rowKey) ? 'unknown' : rowKey,
                String.isBlank(monthKey) ? 'unknown' : monthKey
            }, ':')
        );
        insert commentRecord;
        return commentRecord;
    }

    public static Plant_Volume__c createPlantVolume(
        Id plantId,
        String sector,
        String year,
        String version,
        String monthValue,
        Decimal volume,
        String vehicleBrand,
        String programCode,
        String functionalArea
    ) {
        Plant_Volume__c volumeRow = new Plant_Volume__c(
            Plant__c = plantId,
            Sector__c = sector,
            Calendar_Year__c = year,
            Data_Point_Value__c = version,
            Month__c = monthValue,
            Volume__c = volume
        );
        if (!String.isBlank(vehicleBrand)) {
            volumeRow.Vehicle_Brand__c = vehicleBrand;
        }
      if (!String.isBlank(programCode)) {
            volumeRow.Program_Code__c = programCode;
        }
        if (!String.isBlank(functionalArea)) {
            volumeRow.Functional_Area__c = functionalArea;
        }
        insert volumeRow;
        return volumeRow;
    }

    public static GWB_Vacation_Coverage__c createVacationCoverage(
        Id plantId,
        String sector,
        String year,
        Decimal vacationPercent,
        String entryMonthYear,
        String exitMonthYear
    ) {
        GWB_Vacation_Coverage__c record = new GWB_Vacation_Coverage__c(
            Plant__c = plantId,
            Sector__c = sector,
            Year__c = year,
            Classification__c = 'OTS',
            Vacation_Percent__c = vacationPercent,
            Entry_Month_Year__c = entryMonthYear,
            Exit_Month_Year__c = exitMonthYear
        );
        insert record;
        return record;
    }

    private static String normalizeMonthSection(String section) {
        return normalizePicklistValueWithLegacyHints(
            GWB_Month__c.Section__c,
            section,
            new Map<String, List<String>>{
                normalizeToken(MANPOWER_SECTION_LEGACY) => new List<String>{ 'headcount', 'hours' },
                normalizeToken(SCHEDULED_VOLUME_SECTION_LEGACY) => new List<String>{ 'opplan', 'op plan', 'schedule' }
            }
        );
    }

    private static String normalizeMonthParameter(String parameter) {
        return normalizePicklistValueWithLegacyHints(
            GWB_Month__c.Parameter__c,
            parameter,
            new Map<String, List<String>>{
                normalizeToken('Approved Target') => new List<String>{ 'approved', 'target' }
            }
        );
    }

    private static String normalizePicklistValue(Schema.SObjectField fieldRef, String requestedValue) {
        return normalizePicklistValueWithLegacyHints(fieldRef, requestedValue, new Map<String, List<String>>());
    }

    private static String normalizePicklistValueWithLegacyHints(
        Schema.SObjectField fieldRef,
        String requestedValue,
        Map<String, List<String>> legacyHintsByRequestedToken
    ) {
        List<String> activeValues = new List<String>();
        for (Schema.PicklistEntry entry : fieldRef.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                activeValues.add(entry.getValue());
            }
        }
        if (activeValues.isEmpty()) {
            return requestedValue;
        }
        if (String.isBlank(requestedValue)) {
            return activeValues[0];
        }
        if (activeValues.contains(requestedValue)) {
            return requestedValue;
        }

        String requestedToken = normalizeToken(requestedValue);
        for (String activeValue : activeValues) {
            if (normalizeToken(activeValue) == requestedToken) {
                return activeValue;
            }
        }
        for (String activeValue : activeValues) {
            String activeToken = normalizeToken(activeValue);
            if (activeToken.contains(requestedToken) || requestedToken.contains(activeToken)) {
                return activeValue;
            }
        }

        List<String> hintTerms = legacyHintsByRequestedToken.get(requestedToken);
        if (hintTerms != null && !hintTerms.isEmpty()) {
            for (String activeValue : activeValues) {
                String activeToken = normalizeToken(activeValue);
                for (String hintTerm : hintTerms) {
                    if (activeToken.contains(normalizeToken(hintTerm))) {
                        return activeValue;
                    }
                }
            }
        }

        return activeValues[0];
    }

    private static String normalizeToken(String rawValue) {
        if (rawValue == null) {
            return '';
        }
        String token = rawValue.toLowerCase();
        token = token.replace('_', '');
        token = token.replace(' ', '');
        token = token.replace('/', '');
        token = token.replace('-', '');
        token = token.replace('%', '');
        return token;
    }
}