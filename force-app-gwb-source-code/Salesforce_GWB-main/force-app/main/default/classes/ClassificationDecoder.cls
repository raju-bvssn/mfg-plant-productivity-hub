public with sharing class ClassificationDecoder {
    private static Map<String, String> classificationGroupByValue;
    private static Map<String, Set<String>> classificationValuesByGroup;

    public static String toClassificationGroup(String classification) {
        if (String.isBlank(classification)) {
            return classification;
        }

        String normalizedClassification = normalize(classification);
        Map<String, String> groupByValue = getClassificationGroupByValue();
        return groupByValue.containsKey(normalizedClassification) ? groupByValue.get(normalizedClassification) : null;
    }

    public static Set<String> getClassificationsForGroup(String classificationGroup) {
        String normalizedClassificationGroup = toClassificationGroup(classificationGroup);
        if (String.isBlank(normalizedClassificationGroup)) {
            return new Set<String>();
        }

        Map<String, Set<String>> valuesByGroup = getClassificationValuesByGroup();
        if (!valuesByGroup.containsKey(normalizedClassificationGroup)) {
            return new Set<String>();
        }
        return new Set<String>(valuesByGroup.get(normalizedClassificationGroup));
    }

    private static Map<String, String> getClassificationGroupByValue() {
        loadDecoderMaps();
        return classificationGroupByValue;
    }

    private static Map<String, Set<String>> getClassificationValuesByGroup() {
        loadDecoderMaps();
        return classificationValuesByGroup;
    }

    private static void loadDecoderMaps() {
        if (classificationGroupByValue != null && classificationValuesByGroup != null) {
            return;
        }

        classificationGroupByValue = new Map<String, String>();
        classificationValuesByGroup = new Map<String, Set<String>>();

        for (Classification_Decoder__mdt decoder : Classification_Decoder__mdt.getAll().values()) {
            String classificationValue = normalize(decoder.Classification__c);
            String classificationGroup = normalize(decoder.Classification_Group__c);
            if (String.isBlank(classificationValue) || String.isBlank(classificationGroup)) {
                continue;
            }

            classificationGroupByValue.put(classificationValue, classificationGroup);
            classificationGroupByValue.put(classificationGroup, classificationGroup);

            if (!classificationValuesByGroup.containsKey(classificationGroup)) {
                classificationValuesByGroup.put(classificationGroup, new Set<String>());
            }
            classificationValuesByGroup.get(classificationGroup).add(classificationGroup);
            classificationValuesByGroup.get(classificationGroup).add(classificationValue);
        }
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}