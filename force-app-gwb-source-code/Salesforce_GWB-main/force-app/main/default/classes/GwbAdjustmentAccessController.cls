public without sharing class GwbAdjustmentAccessController {
    @AuraEnabled(cacheable=true)
    public static AdjustmentAccessResult getAdjustmentAccess() {
        AdjustmentAccessResult result = new AdjustmentAccessResult();
        result.hasAdjustmentEditPermission =
            FeatureManagement.checkPermission('Plant_Admin') ||
            FeatureManagement.checkPermission('GWB_System_Admin');
        result.hasAdjustmentCompletionPermission =
            FeatureManagement.checkPermission('Plant_Admin') ||
            FeatureManagement.checkPermission('GWB_System_Admin');
        return result;
    }

    public class AdjustmentAccessResult {
        @AuraEnabled public Boolean hasAdjustmentEditPermission { get; set; }
        @AuraEnabled public Boolean hasAdjustmentCompletionPermission { get; set; }
    }
}