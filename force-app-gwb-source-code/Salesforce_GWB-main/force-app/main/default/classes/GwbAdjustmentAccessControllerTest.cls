@isTest
private class GwbAdjustmentAccessControllerTest {
    @isTest
    static void getAdjustmentAccessReturnsPermissionFlags() {
        GwbAdjustmentAccessController.AdjustmentAccessResult result = GwbAdjustmentAccessController.getAdjustmentAccess();

        Boolean expectedPermission =
            FeatureManagement.checkPermission('Plant_Admin') ||
            FeatureManagement.checkPermission('GWB_System_Admin');

        System.assertNotEquals(null, result, 'Controller should return a result wrapper.');
        System.assertEquals(expectedPermission, result.hasAdjustmentEditPermission, 'Edit permission should mirror feature checks.');
        System.assertEquals(expectedPermission, result.hasAdjustmentCompletionPermission, 'Completion permission should mirror feature checks.');
    }
}