@IsTest
private class PlantSectorTriggerHandlerTest {
    @IsTest
    static void beforeInsertCopiesAuthRegionFromPlant() {
        Plant__c plant = createPlantWithMvp('DT Trigger Auth Region Copy');

        Plant_Sector__c plantSector = new Plant_Sector__c(Plant__c = plant.Id);

        insert plantSector;

        Plant_Sector__c insertedPlantSector = [
            SELECT Id, Plant__c, Auth_Region__c
            FROM Plant_Sector__c
            WHERE Id = :plantSector.Id
        ];
        System.assertEquals(plant.Auth_Region__c, insertedPlantSector.Auth_Region__c, 'Expected Auth Region to be copied from Plant.');
    }

    @IsTest
    static void beforeInsertAllowsDuplicatePlantsAndStillCopiesAuthRegion() {
        Plant__c plant = createPlantWithMvp('DT Trigger Duplicate Plant');

        List<Database.SaveResult> results = Database.insert(
            new List<Plant_Sector__c>{
                new Plant_Sector__c(Plant__c = plant.Id),
                new Plant_Sector__c(Plant__c = plant.Id)
            },
            false
        );

        System.assertEquals(2, results.size(), 'Expected two save results.');
        System.assertEquals(true, results[0].isSuccess(), 'Expected first duplicate insert to succeed.');
        System.assertEquals(true, results[1].isSuccess(), 'Expected second duplicate insert to succeed.');

        List<Plant_Sector__c> insertedPlantSectors = [
            SELECT Id, Auth_Region__c
            FROM Plant_Sector__c
            WHERE Id IN :new Set<Id>{ results[0].getId(), results[1].getId() }
        ];
        System.assertEquals(2, insertedPlantSectors.size(), 'Expected two inserted Plant Sector records.');
        for (Plant_Sector__c insertedPlantSector : insertedPlantSectors) {
            System.assertEquals(
                plant.Auth_Region__c,
                insertedPlantSector.Auth_Region__c,
                'Expected Auth Region to be copied for duplicate inserts in same transaction.'
            );
        }
    }

    @IsTest
    static void beforeInsertDoesNotSetAuthRegionWhenPlantHasNoRegion() {
        Schema.DescribeFieldResult regionDescribe = Plant__c.Auth_Region__c.getDescribe();
        if (!regionDescribe.isNillable()) {
            // In orgs where Plant.Auth_Region__c is required, validate normal copy behavior instead.
            String requiredRegion = getFirstActivePicklistValue(Plant__c.Auth_Region__c);
            Plant__c requiredRegionPlant = createPlantWithMvp('DT Trigger Required Region', requiredRegion);

            Plant_Sector__c requiredRegionPlantSector = new Plant_Sector__c(Plant__c = requiredRegionPlant.Id);
            insert requiredRegionPlantSector;

            Plant_Sector__c insertedRequiredRegionPlantSector = [
                SELECT Id, Auth_Region__c
                FROM Plant_Sector__c
                WHERE Id = :requiredRegionPlantSector.Id
            ];
            System.assertEquals(
                requiredRegionPlant.Auth_Region__c,
                insertedRequiredRegionPlantSector.Auth_Region__c,
                'Expected Auth Region to be copied from Plant when Plant.Auth_Region__c is required.'
            );
            return;
        }

        Plant__c plant = createPlantWithMvp('DT Trigger Null Region', null);

        Plant_Sector__c plantSector = new Plant_Sector__c(Plant__c = plant.Id);
        insert plantSector;

        Plant_Sector__c insertedPlantSector = [
            SELECT Id, Auth_Region__c
            FROM Plant_Sector__c
            WHERE Id = :plantSector.Id
        ];
        System.assertEquals(
            null,
            insertedPlantSector.Auth_Region__c,
            'Expected Auth Region to remain null when Plant.Auth_Region__c is null.'
        );
    }

    @IsTest
    static void handleBeforeInsertSkipsNullPlantRecordsWithoutError() {
        Plant__c plant = createPlantWithMvp('DT Trigger Null Plant Path');
        List<Plant_Sector__c> newRecords = new List<Plant_Sector__c>{
            new Plant_Sector__c(Plant__c = plant.Id),
            new Plant_Sector__c(),
            new Plant_Sector__c(Plant__c = plant.Id)
        };

        Test.startTest();
        PlantSectorTriggerHandler.handleBeforeInsert(newRecords);
        Test.stopTest();

        System.assertEquals(
            plant.Auth_Region__c,
            newRecords[0].Auth_Region__c,
            'Expected handler to populate Auth Region for records with a Plant.'
        );
        System.assertEquals(
            null,
            newRecords[1].Auth_Region__c,
            'Expected handler to skip Auth Region population when Plant__c is null.'
        );
        System.assertEquals(
            plant.Auth_Region__c,
            newRecords[2].Auth_Region__c,
            'Expected duplicate Plant records to still receive Auth Region population.'
        );
    }

    @IsTest
    static void handleBeforeInsertReturnsWhenNoPlantIdsProvided() {
        List<Plant_Sector__c> newRecords = new List<Plant_Sector__c>{
            new Plant_Sector__c(),
            new Plant_Sector__c()
        };

        Test.startTest();
        PlantSectorTriggerHandler.handleBeforeInsert(newRecords);
        Test.stopTest();

        System.assertEquals(null, newRecords[0].Auth_Region__c);
        System.assertEquals(null, newRecords[1].Auth_Region__c);
    }

    private static Plant__c createPlantWithMvp(String name) {
        return createPlantWithMvp(name, getFirstActivePicklistValue(Plant__c.Auth_Region__c));
    }

    private static Plant__c createPlantWithMvp(String name, String authRegion) {
        Plant__c plant = new Plant__c(
            Name = name,
            MVP__c = UserInfo.getUserId()
        );
        if (String.isNotBlank(authRegion)) {
            plant.Auth_Region__c = authRegion;
        } else if (!Plant__c.Auth_Region__c.getDescribe().isNillable()) {
            String fallbackRegion = getFirstActivePicklistValue(Plant__c.Auth_Region__c);
            if (String.isNotBlank(fallbackRegion)) {
                plant.Auth_Region__c = fallbackRegion;
            }
        }
        insert plant;
        return plant;
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldRef) {
        if (fieldRef == null) {
            return null;
        }
        for (Schema.PicklistEntry entry : fieldRef.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }
}