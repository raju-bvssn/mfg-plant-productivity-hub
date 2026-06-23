@IsTest
private class GwbBudgetWorkbenchControllerCommentTest {
    private static Plant__c createPlant() {
        return GWBTestDataFactory.createPlant('Comment Test Plant', true);
    }

    private static GWB_Year__c createBudget(Id plantId) {
        GWB_Year__c budget = GWBTestDataFactory.createGwbYearTarget(
            plantId,
            String.valueOf(Date.today().year()),
            'Draft',
            true
        );
        budget.Version__c = 'CommentTest';
        update budget;
        return budget;
    }

    @IsTest
    static void saveBudgetComment_setsOriginalCreatedDate() {
        Plant__c plantRecord = createPlant();
        GWB_Year__c budget = createBudget(plantRecord.Id);
        GwbBudgetWorkbenchController.elevatedAccessOverride = true;

        Test.startTest();
        GwbBudgetWorkbenchController.CommentDto result = GwbBudgetWorkbenchController.saveBudgetComment(
            budget.Id,
            null,
            'shared',
            'row-1',
            'Row 1',
            'jan',
            'Planning',
            'Created comment',
            '10'
        );
        Test.stopTest();

        GWB_Budget_Comment__c savedComment = [
            SELECT Id, CreatedDate, Original_Created_Date__c, Comment_Text__c
            FROM GWB_Budget_Comment__c
            WHERE Id = :result.id
            LIMIT 1
        ];

        System.assertEquals('Created comment', savedComment.Comment_Text__c);
        System.assertNotEquals(null, savedComment.Original_Created_Date__c, 'Original created date should be set on create.');
        System.assertEquals(savedComment.Original_Created_Date__c, result.createdDate, 'Returned DTO should expose original created date.');
        System.assertNotEquals(null, result.createdDateLabel, 'Returned DTO should include the original created date label.');
    }

    @IsTest
    static void saveBudgetComment_updatesExistingComment() {
        Plant__c plantRecord = createPlant();
        GWB_Year__c budget = createBudget(plantRecord.Id);
        GwbBudgetWorkbenchController.elevatedAccessOverride = true;

        GwbBudgetWorkbenchController.CommentDto insertedComment = GwbBudgetWorkbenchController.saveBudgetComment(
            budget.Id,
            null,
            'shared',
            'row-2',
            'Row 2',
            'feb',
            'Planning',
            'Initial',
            '20'
        );

        Test.startTest();
        GwbBudgetWorkbenchController.CommentDto updatedComment = GwbBudgetWorkbenchController.saveBudgetComment(
            budget.Id,
            insertedComment.id,
            'driver',
            'row-2',
            'Row 2 Updated',
            'mar',
            'Updated',
            'Updated comment',
            '25'
        );
        Test.stopTest();

        GWB_Budget_Comment__c savedComment = [
            SELECT Id, Table_Name__c, Month_Key__c, Comment_Text__c, Original_Created_Date__c
            FROM GWB_Budget_Comment__c
            WHERE Id = :insertedComment.id
            LIMIT 1
        ];
        System.assertEquals('driver', savedComment.Table_Name__c);
        System.assertEquals('mar', savedComment.Month_Key__c);
        System.assertEquals('Updated comment', savedComment.Comment_Text__c);
        System.assertNotEquals(null, savedComment.Original_Created_Date__c);
        System.assertEquals(savedComment.Original_Created_Date__c, updatedComment.createdDate);
    }

    @IsTest
    static void saveBudgetComment_rejectsMissingRequiredInputs() {
        Boolean thrown = false;
        try {
            GwbBudgetWorkbenchController.saveBudgetComment(
                null,
                null,
                'shared',
                null,
                'Row',
                null,
                'Planning',
                null,
                null
            );
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Required comment fields should be validated.');
    }
}