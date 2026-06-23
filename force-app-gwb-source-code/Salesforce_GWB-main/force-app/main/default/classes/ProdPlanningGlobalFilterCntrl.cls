public with sharing class ProdPlanningGlobalFilterCntrl {
    private static final List<String> MONTH_OPTIONS = new List<String>{
        'All',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
    };

    private static final List<String> EXCLUDE_FROM_GWB_OPTIONS = new List<String>{ 'Yes', 'No' };
    private static final String ACTIVE_STATUS = 'Active';

    @AuraEnabled(cacheable=true)
    public static GlobalFilterResponse getGlobalFilters(GlobalFilterRequest requestPayload) {
        GlobalFilterResponse response = new GlobalFilterResponse();
        response.plant = new List<FilterOption>();
        response.shopsByPlant = new Map<String, List<String>>();

        List<Plant__c> plants = [
            SELECT Id, Name, Auth_Region__c
            FROM Plant__c
            WHERE Status__c = :ACTIVE_STATUS
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ];

        Map<Id, String> plantNameById = new Map<Id, String>();
        Set<Id> plantIds = new Set<Id>();
        for (Plant__c plantRecord : plants) {
            String plantRegion = plantRecord.Auth_Region__c == null ? '' : String.valueOf(plantRecord.Auth_Region__c);
            response.plant.add(new FilterOption(plantRecord.Name, (String) plantRecord.Id, plantRegion));
            plantNameById.put(plantRecord.Id, plantRecord.Name);
            plantIds.add(plantRecord.Id);
            response.shopsByPlant.put(plantRecord.Name, new List<String>());
        }

        if (!plantIds.isEmpty()) {
            Map<String, Set<String>> shopsByPlantSet = new Map<String, Set<String>>();
            for (Plant_Function__c plantFunction : [
                SELECT Plant__c, Shop_Manager_View__c
                FROM Plant_Function__c
                WHERE Plant__c IN :plantIds
                AND Status__c = :ACTIVE_STATUS
                AND Shop_Manager_View__c != null
                WITH SECURITY_ENFORCED
            ]) {
                String plantName = plantNameById.get(plantFunction.Plant__c);
                if (String.isBlank(plantName) || String.isBlank(plantFunction.Shop_Manager_View__c)) {
                    continue;
                }

                if (!shopsByPlantSet.containsKey(plantName)) {
                    shopsByPlantSet.put(plantName, new Set<String>());
                }
                shopsByPlantSet.get(plantName).add(plantFunction.Shop_Manager_View__c.trim());
            }

            for (String plantName : shopsByPlantSet.keySet()) {
                List<String> shopValues = new List<String>();
                shopValues.addAll(shopsByPlantSet.get(plantName));
                shopValues.sort();
                response.shopsByPlant.put(plantName, shopValues);
            }
        }

        Integer currentYear = Date.today().year();
        response.year = new List<String>{
            String.valueOf(currentYear - 1),
            String.valueOf(currentYear),
            String.valueOf(currentYear + 1),
            String.valueOf(currentYear + 2)
        };
        response.month = new List<String>(MONTH_OPTIONS);
        response.classification = prependAll(getActivePicklistValues(Initiative__c.Classification__c));
        response.driver = prependAll(getActivePicklistValues(Initiative__c.Driver__c));
        response.baseSupp = prependAll(getActivePicklistValues(Initiative__c.Headcount_Type__c));
        response.initiativeType = prependAll(getActivePicklistValues(Initiative__c.Initiative_Type__c));
        response.initiativeStatus = prependAll(getActivePicklistValues(Initiative__c.Status__c));
        response.excludeFromGWB = new List<String>(EXCLUDE_FROM_GWB_OPTIONS);
        response.lockExcludeFromGWB = shouldLockExcludeFromGWB();

        return response;
    }

    private static Boolean shouldLockExcludeFromGWB() {
        return FeatureManagement.checkPermission('Central_Admin')
            || FeatureManagement.checkPermission('Regional_Admin');
    }

    private static List<String> prependAll(List<String> values) {
        List<String> options = new List<String>{ 'All' };
        if (values != null) {
            options.addAll(values);
        }
        return options;
    }

    private static List<String> getActivePicklistValues(Schema.SObjectField fieldToken) {
        List<String> values = new List<String>();
        if (fieldToken == null) {
            return values;
        }

        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            values.add(entry.getValue());
        }
        return values;
    }

    public class GlobalFilterResponse {
        @AuraEnabled public List<FilterOption> plant;
        @AuraEnabled public Map<String, List<String>> shopsByPlant;
        @AuraEnabled public List<String> year;
        @AuraEnabled public List<String> month;
        @AuraEnabled public List<String> classification;
        @AuraEnabled public List<String> driver;
        @AuraEnabled public List<String> baseSupp;
        @AuraEnabled public List<String> initiativeType;
        @AuraEnabled public List<String> initiativeStatus;
        @AuraEnabled public List<String> excludeFromGWB;
        @AuraEnabled public Boolean lockExcludeFromGWB;
    }

    public class GlobalFilterRequest {
        @AuraEnabled public Id plant;
        @AuraEnabled public String shop;
        @AuraEnabled public String year;
        @AuraEnabled public String month;
        @AuraEnabled public String classification;
        @AuraEnabled public String driver;
        @AuraEnabled public String baseSupp;
        @AuraEnabled public String initiativeType;
        @AuraEnabled public String initiativeStatus;
        @AuraEnabled public String excludeFromGWB;
    }

    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String plantRegion;

        public FilterOption() {}

        public FilterOption(String optionLabel, String optionValue) {
            label = optionLabel;
            value = optionValue;
        }

        public FilterOption(String optionLabel, String optionValue, String optionPlantRegion) {
            label = optionLabel;
            value = optionValue;
            plantRegion = optionPlantRegion;
        }
    }
}