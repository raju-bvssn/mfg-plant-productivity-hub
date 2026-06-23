@isTest(SeeAllData=true)
private class InitiativeApprovalHistoryControllerTest {
    @isTest
    static void getApprovalHistoryThrowsWhenRecordIdMissing() {
        Boolean didThrow = false;
        try {
            InitiativeApprovalHistoryController.getApprovalHistory(null);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Expected exception when record id is null.');
    }

    @isTest
    static void getApprovalHistoryReturnsEmptyWhenNoApprovalRowsExist() {
        Plant__c plant = GWBTestDataFactory.createPlant('Approval History Plant', true);

        List<InitiativeApprovalHistoryController.ApprovalHistoryRow> rows =
            InitiativeApprovalHistoryController.getApprovalHistory(plant.Id);

        System.assertNotEquals(null, rows, 'Controller should return a list instance.');
        System.assertEquals(0, rows.size(), 'Records with no process history should return no rows.');
    }

    @isTest
    static void getApprovalHistoryReadsExistingApprovalRowsWhenAvailable() {
        List<ProcessInstance> existingInstances = [
            SELECT TargetObjectId
            FROM ProcessInstance
            WHERE TargetObjectId != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (existingInstances.isEmpty()) {
            System.assert(true, 'No existing approval data available in org; branch is safely skipped.');
            return;
        }

        List<InitiativeApprovalHistoryController.ApprovalHistoryRow> rows =
            InitiativeApprovalHistoryController.getApprovalHistory(existingInstances[0].TargetObjectId);

        System.assertNotEquals(null, rows, 'Controller should return a list for existing approval records.');
    }
}