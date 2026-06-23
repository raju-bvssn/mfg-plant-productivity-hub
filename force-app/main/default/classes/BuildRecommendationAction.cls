public with sharing class BuildRecommendationAction {

    public class RecommendationRequest {
        @InvocableVariable(label='Plant Name' required=true)
        public String plantName;
        @InvocableVariable(label='Plant Code' required=true)
        public String plantCode;
        @InvocableVariable(label='Shop Name' required=true)
        public String shopName;
        @InvocableVariable(label='Quarter' required=true)
        public String quarter;
        @InvocableVariable(label='Target FTE' required=true)
        public Decimal targetFTE;
        @InvocableVariable(label='Approved FTE Coverage')
        public Decimal approvedFTECoverage;
        @InvocableVariable(label='Gap To Target')
        public Decimal gapToTarget;
        @InvocableVariable(label='Auth Positions')
        public Decimal authPositions;
        @InvocableVariable(label='Current Headcount')
        public Decimal currentHeadcount;
        @InvocableVariable(label='Production Context')
        public String productionContext;
        @InvocableVariable(label='Scored Ideas JSON' required=true)
        public String scoredIdeasJson;
        @InvocableVariable(label='Benchmark Evidence')
        public String benchmarkEvidence;
    }

    public class RecommendationResponse {
        @InvocableVariable(label='Selected Idea Name')
        public String selectedIdeaName;
        @InvocableVariable(label='FTE Impact')
        public Decimal fteImpact;
        @InvocableVariable(label='Dollar Impact')
        public Decimal dollarImpact;
        @InvocableVariable(label='Confidence Score')
        public Integer confidenceScore;
        @InvocableVariable(label='Reasoning')
        public String reasoning;
        @InvocableVariable(label='Required Validations')
        public String requiredValidations;
        @InvocableVariable(label='Raw LLM Response')
        public String rawResponse;
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Build Recommendation' description='Calls PlantIQ_Recommendation Prompt Template via Einstein LLM and parses structured response')
    public static List<RecommendationResponse> buildRecommendation(List<RecommendationRequest> requests) {
        List<RecommendationResponse> responses = new List<RecommendationResponse>();
        for (RecommendationRequest req : requests) {
            responses.add(callLLM(req));
        }
        return responses;
    }

    private static RecommendationResponse callLLM(RecommendationRequest req) {
        RecommendationResponse resp = new RecommendationResponse();
        try {
            // --- Assemble 5 consolidated prompt inputs ---

            // 1. Target_Context — all HQ target and plant identifiers in one block
            String targetContext =
                'Plant: ' + req.plantName + ' (' + req.plantCode + ')\n' +
                'Shop: ' + req.shopName + '\n' +
                'Quarter: ' + req.quarter + '\n' +
                'HQ Target FTE Reduction: ' + req.targetFTE + '\n' +
                'Approved FTE Coverage: ' + (req.approvedFTECoverage != null ? req.approvedFTECoverage : 0) + '\n' +
                'Gap To Target: ' + (req.gapToTarget != null ? req.gapToTarget : req.targetFTE) + ' FTE\n' +
                'Authorized Positions: ' + (req.authPositions != null ? String.valueOf(req.authPositions) : 'N/A') + '\n' +
                'Current Headcount: ' + (req.currentHeadcount != null ? String.valueOf(req.currentHeadcount) : 'N/A');

            // 2. Production_Context
            String productionContext = String.isNotBlank(req.productionContext)
                ? req.productionContext
                : 'Standard production mix';

            // 3. Scored_Ideas_Json — passed through directly from ScoreBenchmarksAction
            String scoredIdeasJson = String.isNotBlank(req.scoredIdeasJson)
                ? req.scoredIdeasJson
                : '[]';

            // 4. Benchmark_Evidence
            String benchmarkEvidence = String.isNotBlank(req.benchmarkEvidence)
                ? req.benchmarkEvidence
                : 'No benchmark evidence available';

            // 5. Guardrails — fixed instructions, not user-supplied
            String guardrails =
                'Select ONLY from the ideas listed in Scored_Ideas_Json. ' +
                'Do not invent new ideas or categories. ' +
                'FTE dollar value = FTE impact x $130,000. ' +
                'Return response in EXACTLY this format:\n' +
                'IDEA: <idea name>\n' +
                'FTE_RANGE: <min>-<max>\n' +
                'DOLLAR_IMPACT: <$ amount>\n' +
                'CONFIDENCE: <score 0-100>\n' +
                'REASONING: <2 sentences max>\n' +
                'VALIDATIONS: <comma-separated list>';

            // --- Call Einstein LLM via Prompt Template ---
            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            promptInput.additionalConfig.applicationName = null;

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:Target_Context',    wrappedString(targetContext));
            inputParams.put('Input:Production_Context', wrappedString(productionContext));
            inputParams.put('Input:Scored_Ideas_JSON',  wrappedString(scoredIdeasJson));
            inputParams.put('Input:Benchmark_Evidence', wrappedString(benchmarkEvidence));
            inputParams.put('Input:Guardrails',         wrappedString(guardrails));

            promptInput.inputParams = inputParams;
            promptInput.isPreview   = false;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    'PlantIQ_Recommendation',
                    promptInput
                );

            String llmText = result.generations[0].text;
            resp.rawResponse = llmText;
            resp.success     = true;

            parseResponse(llmText, resp);

        } catch (Exception e) {
            resp.success      = false;
            resp.errorMessage = e.getMessage();
        }
        return resp;
    }

    // Parse the structured LLM response into discrete fields
    private static void parseResponse(String text, RecommendationResponse resp) {
        for (String line : text.split('\n')) {
            line = line.trim();
            if (line.startsWith('IDEA:')) {
                resp.selectedIdeaName = line.substringAfter('IDEA:').trim();

            } else if (line.startsWith('FTE_RANGE:')) {
                String range = line.substringAfter('FTE_RANGE:').trim();
                // Parse "0.6-1.4" → take midpoint as fteImpact
                if (range.contains('-')) {
                    Decimal lo = Decimal.valueOf(range.substringBefore('-').trim());
                    Decimal hi = Decimal.valueOf(range.substringAfter('-').trim());
                    resp.fteImpact = ((lo + hi) / 2).setScale(1);
                } else {
                    resp.fteImpact = Decimal.valueOf(range);
                }

            } else if (line.startsWith('DOLLAR_IMPACT:')) {
                String raw = line.substringAfter('DOLLAR_IMPACT:').trim()
                    .replace('$', '').replace(',', '').replace('K', '000').trim();
                try {
                    if (raw.contains('-')) {
                        Decimal lo = Decimal.valueOf(raw.substringBefore('-').trim());
                        Decimal hi = Decimal.valueOf(raw.substringAfter('-').trim());
                        resp.dollarImpact = ((lo + hi) / 2).setScale(0);
                    } else {
                        resp.dollarImpact = Decimal.valueOf(raw);
                    }
                } catch (Exception e) {}

            } else if (line.startsWith('CONFIDENCE:')) {
                try { resp.confidenceScore = Integer.valueOf(line.substringAfter('CONFIDENCE:').trim()); } catch (Exception e) {}

            } else if (line.startsWith('REASONING:')) {
                resp.reasoning = line.substringAfter('REASONING:').trim();

            } else if (line.startsWith('VALIDATIONS:')) {
                resp.requiredValidations = line.substringAfter('VALIDATIONS:').trim();
            }
        }
    }

    private static ConnectApi.WrappedValue wrappedString(String val) {
        ConnectApi.WrappedValue w = new ConnectApi.WrappedValue();
        w.value = val;
        return w;
    }
}
