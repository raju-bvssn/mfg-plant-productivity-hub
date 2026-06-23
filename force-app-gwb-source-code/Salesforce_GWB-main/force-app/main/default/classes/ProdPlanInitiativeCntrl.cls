public with sharing class ProdPlanInitiativeCntrl {
    private static final String INITIATIVE_BASE_QUERY =
        'SELECT Id, Classification__c,Description__c,Driver__c,Effective_Date__c,End_Date__c,Exclude_From_GWB__c,Headcount_Type__c,Initiative_Type__c,Name,Plant__c,Plant__r.Name,Position_Adjustment__c,Region__c,Shop_Manager_View__c,Status__c,Total_Calculated_Adjustment__c FROM Initiative__c ';
        private static final String configuredInitiativeType = 'Permanent';
    public ProdPlanInitiativeCntrl() {

    }

    public class InitiativeFilterRequest {
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

    @AuraEnabled
    public static Map<String, Object> getInitiativeRecords(InitiativeFilterRequest request) {
        if (request == null) {
            throw new AuraHandledException('Input payload is required.');
        }

        List<String> whereClauses = new List<String>();
        whereClauses.add('Plant__c = \'' + String.escapeSingleQuotes(request.plant.trim()) + '\'');

        if (shouldApplyFilter(request.shop)) {
            whereClauses.add('Shop_Manager_View__c = \'' + String.escapeSingleQuotes(request.shop) + '\'');
        }

        if (shouldApplyFilter(request.year)) {
            Integer yearValue = Integer.valueOf(request.year);
            whereClauses.add('CALENDAR_YEAR(Effective_Date__c) = ' + yearValue);
        }

        Integer monthValue = shouldApplyFilter(request.month) ? parseMonth(request.month) : null;
        if (monthValue != null) {
            whereClauses.add('CALENDAR_MONTH(Effective_Date__c) = ' + monthValue);
        }

        if (shouldApplyFilter(request.driver)) {
            whereClauses.add('Driver__c = \'' + String.escapeSingleQuotes(request.driver) + '\'');
        }

        if (shouldApplyFilter(request.classification)) {
            whereClauses.add('Classification__c = \'' + String.escapeSingleQuotes(request.classification) + '\'');
        }

        if (shouldApplyFilter(request.baseSupp)) {
            whereClauses.add('Headcount_Type__c = \'' + String.escapeSingleQuotes(request.baseSupp) + '\'');
        }
        
        if (String.isNotBlank(configuredInitiativeType)) {
            whereClauses.add('Initiative_Type__c = \'' + String.escapeSingleQuotes(configuredInitiativeType) + '\'');
        }

        if (shouldApplyFilter(request.initiativeStatus)) {
            whereClauses.add('Status__c = \'' + String.escapeSingleQuotes(request.initiativeStatus) + '\'');
        }

        if (shouldApplyFilter(request.excludeFromGWB)) {
            String normalizedExcludeFromGwb = request.excludeFromGWB.trim().toLowerCase();
            if ('yes'.equalsIgnoreCase(normalizedExcludeFromGwb)) {
                whereClauses.add('Exclude_From_GWB__c = true');
            } else if ('no'.equalsIgnoreCase(normalizedExcludeFromGwb)) {
                whereClauses.add('Exclude_From_GWB__c = false');
            }
        }

        String finalQuery = INITIATIVE_BASE_QUERY + ' WHERE ' + String.join(whereClauses, ' AND ');
        List<Initiative__c> records = Database.query(finalQuery);

        return new Map<String, Object>{
            'query' => finalQuery,
            'records' => records
        };
    }

    private static Integer parseMonth(String monthInput) {
        if (String.isBlank(monthInput)) {
            return null;
        }

        String normalizedMonth = monthInput.trim().toLowerCase();
        Map<String, Integer> monthMap = new Map<String, Integer>{
            'january' => 1,
            'february' => 2,
            'march' => 3,
            'april' => 4,
            'may' => 5,
            'june' => 6,
            'july' => 7,
            'august' => 8,
            'september' => 9,
            'october' => 10,
            'november' => 11,
            'december' => 12
        };

        if (monthMap.containsKey(normalizedMonth)) {
            return monthMap.get(normalizedMonth);
        }

        if (Pattern.matches('^\\d{1,2}$', normalizedMonth)) {
            Integer numericMonth = Integer.valueOf(normalizedMonth);
            if (numericMonth >= 1 && numericMonth <= 12) {
                return numericMonth;
            }
        }

        return null;
    }

    private static Boolean shouldApplyFilter(String value) {
        return String.isNotBlank(value) && value.trim().toLowerCase() != 'all';
    }
}