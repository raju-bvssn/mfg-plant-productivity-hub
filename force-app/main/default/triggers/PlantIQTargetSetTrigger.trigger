// Apex fallback: only runs if the env var MULESOFT_ACTIVE is not set to true.
// Primary path is MuleSoft subscribing to this same Platform Event via replay-channel-listener.
// To re-enable: remove the short-circuit condition below.
trigger PlantIQTargetSetTrigger on PlantIQ_Target_Set__e (after insert) {
    List<PlantIQ_Config__mdt> cfg = [
        SELECT Value__c FROM PlantIQ_Config__mdt
        WHERE DeveloperName = 'MuleSoft_Active' LIMIT 1
    ];
    Boolean mulesoftActive = !cfg.isEmpty() && cfg[0].Value__c == 'true';
    if (!mulesoftActive) {
        PlantIQRecommendationOrchestrator.run(Trigger.new);
    }
}
