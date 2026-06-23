@IsTest
private class ProdPlanInitiativeCntrlTest {
    @IsTest
    static void getInitiativeRecordsThrowsWhenRequestIsNull() {
        Test.startTest();
        try {
            ProdPlanInitiativeCntrl.getInitiativeRecords(null);
            System.assert(false, 'Expected an AuraHandledException when request is null.');
        } catch (AuraHandledException ex) {
            System.assertEquals('Script-thrown exception', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void getInitiativeRecordsBuildsFiltersAndReturnsMatchingRows() {
        Plant__c plant = GWBTestDataFactory.createPlant('Prod Plan Plant', true);
        Date effectiveDate = Date.newInstance(Date.today().year(), 1, 10);
        Date endDate = Date.newInstance(Date.today().year(), 12, 20);

        String classification = getActivePicklistValue(
            Initiative__c.Classification__c,
            new List<String>{ 'OTS', 'Direct OTS' }
        );
        String driver = getActivePicklistValue(
            Initiative__c.Driver__c,
            new List<String>{ 'Productivity', 'Op Plan' }
        );
        String headcountType = getActivePicklistValue(
            Initiative__c.Headcount_Type__c,
            new List<String>{ 'Base', 'SUPP' }
        );
        String initiativeType = getActivePicklistValue(
            Initiative__c.Initiative_Type__c,
            new List<String>{ 'Productivity', 'Operating' }
        );
        String initiativeStatus = getActivePicklistValue(
            Initiative__c.Status__c,
            new List<String>{ 'Active', 'Draft' }
        );
        String region = getActivePicklistValue(
            Initiative__c.Region__c,
            new List<String>{ 'GMNA' }
        );

        Initiative__c matchingInitiative = new Initiative__c(
            Plant__c = plant.Id,
            Classification__c = classification,
            Description__c = 'Matching initiative',
            Driver__c = driver,
            Effective_Date__c = effectiveDate,
            End_Date__c = endDate,
            Exclude_From_GWB__c = true,
            Headcount_Type__c = headcountType,
            Initiative_Type__c = initiativeType,
            Position_Adjustment__c = 5,
            Region__c = region,
            Shop_Manager_View__c = 'Body',
            Status__c = initiativeStatus
        );
        insert matchingInitiative;

        Initiative__c nonMatchingInitiative = new Initiative__c(
            Plant__c = plant.Id,
            Classification__c = classification,
            Description__c = 'Non matching initiative',
            Driver__c = driver,
            Effective_Date__c = effectiveDate,
            End_Date__c = endDate,
            Exclude_From_GWB__c = false,
            Headcount_Type__c = headcountType,
            Initiative_Type__c = initiativeType,
            Position_Adjustment__c = 2,
            Region__c = region,
            Shop_Manager_View__c = 'Paint',
            Status__c = initiativeStatus
        );
        insert nonMatchingInitiative;

        ProdPlanInitiativeCntrl.InitiativeFilterRequest request = new ProdPlanInitiativeCntrl.InitiativeFilterRequest();
        request.plant = String.valueOf(plant.Id);
        request.shop = 'Body';
        request.year = String.valueOf(Date.today().year());
        request.month = 'January';
        request.classification = classification;
        request.driver = driver;
        request.baseSupp = headcountType;
        request.initiativeType = initiativeType;
        request.initiativeStatus = initiativeStatus;
        request.excludeFromGWB = 'Yes';

        Test.startTest();
        Map<String, Object> response = ProdPlanInitiativeCntrl.getInitiativeRecords(request);
        Test.stopTest();

        String query = (String) response.get('query');
        List<Initiative__c> rows = (List<Initiative__c>) response.get('records');

        System.assert(query.contains('Plant__c = \'' + String.valueOf(plant.Id) + '\''));
        System.assert(query.contains('Shop_Manager_View__c = \'Body\''));
        System.assert(query.contains('CALENDAR_MONTH(Effective_Date__c) = 1'));
        System.assert(query.contains('Exclude_From_GWB__c = true'));
        System.assertEquals(1, rows.size(), 'Expected only one initiative to match all filters.');
        System.assertEquals(matchingInitiative.Id, rows[0].Id);
    }

    @IsTest
    static void getInitiativeRecordsSkipsAllAndInvalidMonthFilters() {
        Plant__c plant = GWBTestDataFactory.createPlant('Prod Plan Plant 2', true);
        String classification = getActivePicklistValue(Initiative__c.Classification__c, null);
        String driver = getActivePicklistValue(Initiative__c.Driver__c, null);
        String headcountType = getActivePicklistValue(Initiative__c.Headcount_Type__c, null);
        String initiativeType = getActivePicklistValue(Initiative__c.Initiative_Type__c, null);
        String initiativeStatus = getActivePicklistValue(Initiative__c.Status__c, null);
        String region = getActivePicklistValue(Initiative__c.Region__c, null);

        insert new Initiative__c(
            Plant__c = plant.Id,
            Classification__c = classification,
            Description__c = 'All-filter initiative',
            Driver__c = driver,
            Effective_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(15),
            Exclude_From_GWB__c = false,
            Headcount_Type__c = headcountType,
            Initiative_Type__c = initiativeType,
            Position_Adjustment__c = 1,
            Region__c = region,
            Shop_Manager_View__c = 'Trim',
            Status__c = initiativeStatus
        );

        ProdPlanInitiativeCntrl.InitiativeFilterRequest request = new ProdPlanInitiativeCntrl.InitiativeFilterRequest();
        request.plant = String.valueOf(plant.Id);
        request.shop = 'All';
        request.year = 'All';
        request.month = 'NotAMonth';
        request.classification = 'All';
        request.driver = 'All';
        request.baseSupp = 'All';
        request.initiativeType = 'All';
        request.initiativeStatus = 'All';
        request.excludeFromGWB = 'No';

        Test.startTest();
        Map<String, Object> response = ProdPlanInitiativeCntrl.getInitiativeRecords(request);
        Test.stopTest();

        String query = (String) response.get('query');
        List<Initiative__c> rows = (List<Initiative__c>) response.get('records');

        System.assert(!query.contains('Shop_Manager_View__c ='));
        System.assert(!query.contains('CALENDAR_MONTH(Effective_Date__c) ='));
        System.assert(query.contains('Exclude_From_GWB__c = false'));
        System.assertEquals(1, rows.size(), 'Expected plant-only + exclude filter to keep inserted row.');
    }

    private static String getActivePicklistValue(Schema.SObjectField fieldRef, List<String> preferredValues) {
        List<Schema.PicklistEntry> entries = fieldRef.getDescribe().getPicklistValues();
        if (preferredValues != null) {
            Set<String> preferredSet = new Set<String>(preferredValues);
            for (Schema.PicklistEntry entry : entries) {
                if (entry.isActive() && preferredSet.contains(entry.getValue())) {
                    return entry.getValue();
                }
            }
        }

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }
}