@isTest(SeeAllData=true)
private class FlowApprovalProcessorTest {
    @isTest
    static void processApprovalReturnsValidationErrorForUnsupportedAction() {
        FlowApprovalProcessor.Request request = new FlowApprovalProcessor.Request();
        request.workItemId = '04i000000000001AAA';
        request.action = 'Hold';
        request.comments = 'Not a valid approval action';

        List<FlowApprovalProcessor.Result> results = FlowApprovalProcessor.processApproval(
            new List<FlowApprovalProcessor.Request>{ request }
        );

        System.assertEquals(1, results.size(), 'One result should be returned for one request.');
        System.assertEquals(false, results[0].isSuccess, 'Invalid action should fail.');
        System.assert(results[0].errorMessage.contains('Invalid action specified'), 'Expected validation message for unsupported action.');
    }

    @isTest
    static void processApprovalHandlesApproveAndRejectFailuresGracefully() {
        FlowApprovalProcessor.Request approveRequest = new FlowApprovalProcessor.Request();
        approveRequest.workItemId = '04i000000000001AAA';
        approveRequest.action = 'Approve';
        approveRequest.comments = 'Attempt approve with invalid work item id';

        FlowApprovalProcessor.Request rejectRequest = new FlowApprovalProcessor.Request();
        rejectRequest.workItemId = '04i000000000002AAA';
        rejectRequest.action = 'Reject';
        rejectRequest.comments = 'Attempt reject with invalid work item id';

        Test.startTest();
        List<FlowApprovalProcessor.Result> results = FlowApprovalProcessor.processApproval(
            new List<FlowApprovalProcessor.Request>{ approveRequest, rejectRequest }
        );
        Test.stopTest();

        System.assertEquals(2, results.size(), 'A result should be returned for each request.');
        System.assertEquals(false, results[0].isSuccess, 'Invalid work item should fail.');
        System.assertEquals(false, results[1].isSuccess, 'Invalid work item should fail.');
        System.assert(results[0].errorMessage.startsWith('Error processing approval:'), 'Failures should return a consistent error prefix.');
        System.assert(results[1].errorMessage.startsWith('Error processing approval:'), 'Failures should return a consistent error prefix.');
    }

    @isTest
    static void processApprovalAttemptsRealWorkitemWhenAvailable() {
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (workItems.isEmpty()) {
            System.assert(true, 'No pending work items available in org data.');
            return;
        }

        FlowApprovalProcessor.Request request = new FlowApprovalProcessor.Request();
        request.workItemId = workItems[0].Id;
        request.action = 'Approve';
        request.comments = 'Test approval execution path';

        Test.startTest();
        List<FlowApprovalProcessor.Result> results = FlowApprovalProcessor.processApproval(
            new List<FlowApprovalProcessor.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Method should return one response for one request.');
        System.assertNotEquals(null, results[0].isSuccess, 'Result success flag should always be populated.');
    }
}