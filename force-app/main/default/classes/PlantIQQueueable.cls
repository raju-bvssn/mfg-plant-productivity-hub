public class PlantIQQueueable implements Queueable, Database.AllowsCallouts {

    private Id targetId;

    public PlantIQQueueable(Id targetId) {
        this.targetId = targetId;
    }

    public void execute(QueueableContext ctx) {
        PlantIQRecommendationOrchestrator.run(targetId);
    }
}
