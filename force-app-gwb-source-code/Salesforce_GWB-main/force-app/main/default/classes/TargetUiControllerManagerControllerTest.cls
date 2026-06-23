@isTest
private class TargetUiControllerManagerControllerTest {
    private static TargetUiControllerManagerController.UpsertRecordRequest buildValidRequest() {
        TargetUiControllerManagerController.UpsertRecordRequest requestPayload =
            new TargetUiControllerManagerController.UpsertRecordRequest();
        requestPayload.sector = 'Assembly';
        requestPayload.category = 'Headcount';
        requestPayload.parameterDriver = 'Driver Label';
        requestPayload.sourceType = 'Driver';
        requestPayload.uiLineType = 'Input';
        requestPayload.uiSequence = 10;
        requestPayload.internalKey = 'HC_DRIVER_1';
        requestPayload.valueType = 'number';
        requestPayload.classification = 'salary';
        requestPayload.sourceSection = 'Driver Section';
        requestPayload.sourceValue = 'Total Driver';
        requestPayload.isEditable = true;
        requestPayload.isActive = true;
        requestPayload.fillForwardOnEdit = false;
        requestPayload.formulaKey = 'FORMULA_1';
        requestPayload.formulaTooltip = 'Tooltip';
        return requestPayload;
    }

    @isTest
    static void getManagerDataReturnsResponseShape() {
        Test.startTest();
        TargetUiControllerManagerController.ManagerDataResponse response =
            TargetUiControllerManagerController.getManagerData('__ALL__', 'driver', true);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Expected a response wrapper.');
        System.assertNotEquals(null, response.rows, 'Rows collection should be initialized.');
        System.assertNotEquals(null, response.editorOptions, 'Editor options should be initialized.');
        System.assertNotEquals(null, response.editorOptions.sectorOptions, 'Sector options should be initialized.');
        System.assert(response.totalCount >= 0, 'Total count should be populated.');
        System.assert(response.filteredCount >= 0, 'Filtered count should be populated.');
    }

    @isTest
    static void upsertRejectsEmptyPayloadList() {
        Boolean didThrow = false;
        try {
            TargetUiControllerManagerController.upsertTargetUiControllerRecords(new List<TargetUiControllerManagerController.UpsertRecordRequest>());
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Expected exception for empty payload list.');
    }

    @isTest
    static void upsertRejectsMissingRequiredFields() {
        TargetUiControllerManagerController.UpsertRecordRequest requestPayload =
            new TargetUiControllerManagerController.UpsertRecordRequest();
        requestPayload.sector = 'Assembly';

        Boolean didThrow = false;
        try {
            TargetUiControllerManagerController.upsertTargetUiControllerRecord(requestPayload);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Expected exception for missing required fields.');
    }

    @isTest
    static void upsertSingleRequestBuildsQueuedResult() {
        TargetUiControllerManagerController.UpsertRecordRequest requestPayload = buildValidRequest();
        requestPayload.developerName = null;
        requestPayload.masterLabel = null;
        requestPayload.category = 'Headcount';
        requestPayload.sectionName = null;
        requestPayload.classification = 'mschedule';

        Test.startTest();
        TargetUiControllerManagerController.DeployRequestResult result =
            TargetUiControllerManagerController.upsertTargetUiControllerRecord(requestPayload);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected a deploy request result.');
        System.assertEquals(true, result.queued, 'Result should indicate queued deployment.');
        System.assertEquals(1, result.recordCount, 'Single payload should report one record.');
        System.assertNotEquals(null, result.deploymentId, 'Test-mode deployment id should be populated.');
        System.assertNotEquals(null, result.developerName, 'Generated developer name should be returned.');
        System.assert(result.message.contains('Queued metadata deployment'), 'Expected queued deployment message.');
    }

    @isTest
    static void upsertMultipleRequestsSupportsSanitizedDeveloperName() {
        TargetUiControllerManagerController.UpsertRecordRequest firstRequest = buildValidRequest();
        firstRequest.developerName = '123 Invalid Developer Name !@# TooLong_TooLong_TooLong';
        firstRequest.masterLabel = '   First Label   ';
        firstRequest.category = 'op plan input';
        firstRequest.uiSequence = 2;

        TargetUiControllerManagerController.UpsertRecordRequest secondRequest = buildValidRequest();
        secondRequest.internalKey = 'HC_DRIVER_2';
        secondRequest.parameterDriver = 'Second Driver';
        secondRequest.category = 'Hours';
        secondRequest.uiSequence = 3;
        secondRequest.valueType = 'decimal';

        Test.startTest();
        TargetUiControllerManagerController.DeployRequestResult result =
            TargetUiControllerManagerController.upsertTargetUiControllerRecords(
                new List<TargetUiControllerManagerController.UpsertRecordRequest>{ firstRequest, secondRequest }
            );
        Test.stopTest();

        System.assertEquals(2, result.recordCount, 'Two payloads should report two records.');
        System.assertEquals(true, result.queued, 'Result should indicate queued deployment.');
        System.assert(result.developerName.startsWith('R_'), 'Sanitized name should be prefixed when starting with a number.');
        System.assert(result.developerName.length() <= 40, 'Developer name should remain within metadata length limit.');
        System.assertEquals('First Label', result.masterLabel, 'Master label should be trimmed and returned.');
    }

    @isTest
    static void getDeploymentStatusValidatesInputAndReturnsTestStatus() {
        Boolean didThrow = false;
        try {
            TargetUiControllerManagerController.getDeploymentStatus(null);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Expected exception when deployment id is missing.');

        TargetUiControllerManagerController.DeployStatusResult status =
            TargetUiControllerManagerController.getDeploymentStatus('TEST-DEPLOYMENT-ID');
        System.assertEquals(true, status.done, 'Test-mode status should report done.');
        System.assertEquals(true, status.success, 'Test-mode status should report success.');
        System.assertEquals('Succeeded', status.status, 'Test-mode status should be Succeeded.');
    }
}