public with sharing class PlantIQRecommendationOrchestrator {

    // Called from PlantIQQueueable (Queueable runs as the triggering user, not Automated Process)
    public static void run(Id targetId) {
        try {
            processTarget(targetId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[PlantIQ] Orchestrator error for target ' + targetId + ': ' + e.getMessage());
        }
    }

    // Kept for backward compatibility with the Platform Event trigger if still active
    public static void run(List<PlantIQ_Target_Set__e> events) {
        for (PlantIQ_Target_Set__e evt : events) {
            try {
                processTarget(evt.Target_Id__c);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    '[PlantIQ] Orchestrator error for target ' + evt.Target_Id__c + ': ' + e.getMessage());
            }
        }
    }

    private static void processTarget(Id targetId) {

        // Step 1 — Retrieve plant context from HQ Target
        List<RetrievePlantContextAction.PlantContext> ctxList =
            RetrievePlantContextAction.getContext(new List<Id>{ targetId });
        if (ctxList.isEmpty()) {
            System.debug('[PlantIQ] No context returned for target: ' + targetId);
            return;
        }
        RetrievePlantContextAction.PlantContext ctx = ctxList[0];

        System.debug('[PlantIQ] Context: ' + ctx.plantCode + ' / ' + ctx.shopName +
                     ' | Gap: ' + ctx.gapToTarget + ' FTE | Signal: ' + ctx.recentSignalType);

        // Step 2 — Match Idea Library using most recent signal type from this shop
        MatchIdeaLibraryAction.MatchRequest matchReq = new MatchIdeaLibraryAction.MatchRequest();
        matchReq.signalType = String.isNotBlank(ctx.recentSignalType) ? ctx.recentSignalType : 'Bin-Depletion';
        matchReq.maxResults = 5;

        List<MatchIdeaLibraryAction.MatchResponse> matchList =
            MatchIdeaLibraryAction.matchIdeas(new List<MatchIdeaLibraryAction.MatchRequest>{ matchReq });
        if (matchList.isEmpty() || String.isBlank(matchList[0].matchedIdeasJson)) {
            System.debug('[PlantIQ] No ideas matched for signal type: ' + matchReq.signalType);
            return;
        }
        MatchIdeaLibraryAction.MatchResponse matched = matchList[0];
        System.debug('[PlantIQ] Matched ideas: ' + matched.matchedIdeasJson);

        // Step 3 — Score benchmarks
        ScoreBenchmarksAction.ScoreRequest scoreReq = new ScoreBenchmarksAction.ScoreRequest();
        scoreReq.matchedIdeasJson = matched.matchedIdeasJson;
        scoreReq.shopType         = ctx.shopType;
        scoreReq.productionContext = ctx.productionContext;

        List<ScoreBenchmarksAction.ScoreResponse> scoreList =
            ScoreBenchmarksAction.score(new List<ScoreBenchmarksAction.ScoreRequest>{ scoreReq });
        if (scoreList.isEmpty()) {
            System.debug('[PlantIQ] Scoring returned no results');
            return;
        }
        ScoreBenchmarksAction.ScoreResponse scored = scoreList[0];
        System.debug('[PlantIQ] Top idea: ' + scored.topIdeaName + ' | Score: ' + scored.topConfidenceScore);

        // Step 4 — Build recommendation via Einstein LLM + Prompt Template
        BuildRecommendationAction.RecommendationRequest recReq = new BuildRecommendationAction.RecommendationRequest();
        recReq.plantName           = ctx.plantName;
        recReq.plantCode           = ctx.plantCode;
        recReq.shopName            = ctx.shopName;
        recReq.quarter             = ctx.quarter;
        recReq.targetFTE           = ctx.targetFTE;
        recReq.approvedFTECoverage = ctx.approvedFTECoverage;
        recReq.gapToTarget         = ctx.gapToTarget;
        recReq.authPositions       = ctx.authPositions;
        recReq.currentHeadcount    = ctx.currentHeadcount;
        recReq.productionContext   = ctx.productionContext;
        recReq.scoredIdeasJson     = scored.scoredIdeasJson;
        recReq.benchmarkEvidence   = scored.topBenchmarkEvidence;

        List<BuildRecommendationAction.RecommendationResponse> recList =
            BuildRecommendationAction.buildRecommendation(
                new List<BuildRecommendationAction.RecommendationRequest>{ recReq });
        if (recList.isEmpty() || !recList[0].success) {
            System.debug('[PlantIQ] LLM recommendation failed: ' +
                (recList.isEmpty() ? 'no response' : recList[0].errorMessage));
            return;
        }
        BuildRecommendationAction.RecommendationResponse rec = recList[0];
        System.debug('[PlantIQ] Recommendation: ' + rec.selectedIdeaName + ' | FTE: ' + rec.fteImpact);

        // Step 5 — Create Productivity Idea record
        String ideaTitle = ctx.plantCode + ' ' + ctx.shopName + ': ' + rec.selectedIdeaName;
        CreateIdeaRecordAction.CreateIdeaRequest ideaReq = new CreateIdeaRecordAction.CreateIdeaRequest();
        ideaReq.plantFunctionId    = ctx.plantFunctionId;
        ideaReq.ideaLibraryId      = scored.topIdeaId;
        ideaReq.ideaTitle          = ideaTitle;
        ideaReq.fteImpact          = rec.fteImpact;
        ideaReq.dollarImpact       = rec.dollarImpact;
        ideaReq.confidenceScore    = rec.confidenceScore;
        ideaReq.effort             = scored.topIdeaName != null ? 'Low' : null;
        ideaReq.assumptions        = rec.reasoning;
        ideaReq.benchmarkEvidence  = scored.topBenchmarkEvidence;
        ideaReq.requiredValidations = rec.requiredValidations;

        List<CreateIdeaRecordAction.CreateIdeaResponse> ideaList =
            CreateIdeaRecordAction.createIdea(
                new List<CreateIdeaRecordAction.CreateIdeaRequest>{ ideaReq });
        if (ideaList.isEmpty() || !ideaList[0].success) {
            System.debug('[PlantIQ] Failed to create idea: ' +
                (ideaList.isEmpty() ? 'no response' : ideaList[0].errorMessage));
            return;
        }
        Id ideaId = ideaList[0].ideaId;
        System.debug('[PlantIQ] Created idea record: ' + ideaId);

        // Step 6 — Post to Slack via @future to avoid DML-before-callout governor error
        PostToSlackAction.postAsync(
            ideaId,
            ctx.plantName,
            ctx.shopName,
            ctx.gapToTarget,
            ctx.quarter,
            ideaTitle,
            rec.fteImpact,
            rec.dollarImpact,
            rec.confidenceScore,
            ideaReq.effort,
            scored.topBenchmarkEvidence
        );
        System.debug('[PlantIQ] Slack post queued via @future for idea: ' + ideaId);
    }
}
