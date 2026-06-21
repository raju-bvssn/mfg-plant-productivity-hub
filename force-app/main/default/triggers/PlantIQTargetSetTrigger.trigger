trigger PlantIQTargetSetTrigger on PlantIQ_Target_Set__e (after insert) {
    PlantIQRecommendationOrchestrator.run(Trigger.new);
}
