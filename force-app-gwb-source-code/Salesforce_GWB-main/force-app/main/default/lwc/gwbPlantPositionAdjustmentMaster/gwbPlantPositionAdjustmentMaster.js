import { LightningElement, track, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId, IsConsoleNavigation, openSubtab } from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasPlantAdminPermission from '@salesforce/customPermission/Plant_Admin';
import hasGwbSystemAdminPermission from '@salesforce/customPermission/GWB_System_Admin';
import getAdjustmentAccess from '@salesforce/apex/GwbAdjustmentAccessController.getAdjustmentAccess';
import getPlantShopTargetAdjustments from '@salesforce/apex/PlantShopTargetAdjustmentCntrl.getPlantShopTargetAdjustments';
import updatePlantShopTargetAdjustments from '@salesforce/apex/PlantShopTargetAdjustmentCntrl.updatePlantShopTargetAdjustments';
import getGlobalFilters from '@salesforce/apex/PlantShopTargetAdjustmentCntrl.getGlobalFilters';
import finalizeTarget from '@salesforce/apex/PlantShopTargetAdjustmentCntrl.finalizeTarget';
import getTargetPlantFunctionList from '@salesforce/apex/PlantShopTargetAdjustmentCntrl.getTargetPlantFunctionList';

const MONTH_ORDER = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
];

const CLASSIFICATION_ORDER = ['OTS', 'Skilled', 'Salaried'];
const DRIVER_ORDER = ['Productivity', 'MBC', 'LMS', 'Op Plan'];
const ALL_OPTION = 'All';
const ENABLE_BALANCE_STATUS_FILTER = true;
const MISMATCH_ONLY_OPTION = 'Mismatched Only';
const SECTION_BATCH_SIZE = 8;
const LOAD_MORE_SCROLL_OFFSET = 160;
const MODAL_FUNCTION_BATCH_SIZE = 100;
const MODAL_FUNCTION_LOAD_MORE_OFFSET = 160;
const CLASSIFICATION_LABEL_MAP = {
    OTS: 'OTS',
    SK: 'Skilled',
    SKILLED: 'Skilled',
    SAL: 'Salaried',
    SALARY: 'Salaried',
    SALARIED: 'Salaried'
};
const DRIVER_LABEL_MAP = {
    PRODUCTIVITY: 'Productivity',
    ARC: 'MBC',
    MBC: 'MBC',
    LMS: 'LMS',
    'OP PLAN': 'Op Plan'
};
const COMPONENT_LOG_PREFIX = '[gwbPlantPositionAdjustmentMaster]';
const EMPTY_RESPONSE = {
    target: {
        id: null,
        name: '',
        regionName: '',
        plantName: '',
        scheduleLabel: '',
        status: ''
    },
    sections: []
};

function slugify(value) {
    return value.toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

function deepClone(value) {
    return JSON.parse(JSON.stringify(value));
}

function sortByOrder(values, order) {
    return [...values].sort((left, right) => {
        const leftIndex = order.indexOf(left);
        const rightIndex = order.indexOf(right);
        const normalizedLeft = leftIndex === -1 ? Number.MAX_SAFE_INTEGER : leftIndex;
        const normalizedRight = rightIndex === -1 ? Number.MAX_SAFE_INTEGER : rightIndex;
        if (normalizedLeft !== normalizedRight) {
            return normalizedLeft - normalizedRight;
        }
        return left.localeCompare(right);
    });
}

function formatSignedNumber(value) {
    return Number(value || 0).toLocaleString('en-US', {
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
    });
}

function toFiniteNumber(value, fallback = 0) {
    const numericValue = Number(value);
    return Number.isFinite(numericValue) ? numericValue : fallback;
}

function sectionSort(left, right) {
    const monthCompare = MONTH_ORDER.indexOf(left.month) - MONTH_ORDER.indexOf(right.month);
    if (monthCompare !== 0) {
        return monthCompare;
    }
    const classCompare = CLASSIFICATION_ORDER.indexOf(left.classification) - CLASSIFICATION_ORDER.indexOf(right.classification);
    if (classCompare !== 0) {
        return classCompare;
    }
    return DRIVER_ORDER.indexOf(left.driver) - DRIVER_ORDER.indexOf(right.driver);
}

function buildShopKey(sectionId, shopId) {
    return `${sectionId}::${shopId}`;
}

function buildFunctionKey(sectionId, shopId, functionId) {
    return `${buildShopKey(sectionId, shopId)}::${functionId}`;
}

function buildFunctionFieldKey(sectionId, shopId, functionId, field) {
    return `${buildFunctionKey(sectionId, shopId, functionId)}::${field}`;
}

function getDefaultFilterValues(sections) {
    return {
        month: ALL_OPTION,
        classification: ALL_OPTION,
        driver: ALL_OPTION
    };
}

function getClassificationBandClass(classification) {
    if (classification === 'OTS') {
        return 'classification-band classification-band_ots';
    }
    if (classification === 'Skilled') {
        return 'classification-band classification-band_skilled';
    }
    if (classification === 'Salaried') {
        return 'classification-band classification-band_salaried';
    }
    return 'classification-band';
}

function getChangedCellClass(isChanged) {
    return isChanged ? 'value-col value-col_changed' : 'value-col';
}

function normalizeFilterLabel(type, value) {
    if (type === 'classification') {
        return normalizeClassificationValue(value);
    }
    if (type === 'driver') {
        return normalizeDriverValue(value);
    }
    return String(value || '').trim();
}

function normalizeFilterOptionList(type, values = []) {
    const normalizedValues = values
        .map((item) => {
            const rawValue = typeof item === 'string' ? item : item?.value ?? item?.label ?? '';
            return normalizeFilterLabel(type, rawValue);
        })
        .filter(Boolean);

    const uniqueValues = [...new Set(normalizedValues.filter((value) => value !== ALL_OPTION))];
    return normalizedValues.includes(ALL_OPTION) ? [ALL_OPTION, ...uniqueValues] : [ALL_OPTION, ...uniqueValues];
}

function normalizeFilterOptionMap(type, optionMap = {}) {
    const normalizedMap = {};
    Object.entries(optionMap || {}).forEach(([key, values]) => {
        normalizedMap[key] = normalizeFilterOptionList(type, values);
    });
    return normalizedMap;
}

function getFirstNonAllValue(values = []) {
    return values.find((value) => value && value !== ALL_OPTION) || '';
}

function normalizeGlobalFilters(rawFilters) {
    const source = parseResponse(rawFilters);
    const defaults = source.defaults || {};
    const classificationByMonth = normalizeFilterOptionMap(
        'classification',
        source.classificationByMonth || {}
    );
    const driverByClassification = normalizeFilterOptionMap(
        'driver',
        source.driverByClassification || {}
    );
    const months = normalizeFilterOptionList('month', source.months || source.monthOptions || []);
    const classifications = normalizeFilterOptionList(
        'classification',
        source.classifications ||
            source.classificationOptions ||
            classificationByMonth[ALL_OPTION] ||
            Object.values(classificationByMonth).flat()
    );
    const drivers = normalizeFilterOptionList(
        'driver',
        source.drivers ||
            source.driverOptions ||
            Object.values(driverByClassification).flat()
    );
    return {
        months,
        classifications,
        drivers,
        classificationByMonth,
        driverByClassification,
        defaults: {
            month: ALL_OPTION,
            classification: ALL_OPTION,
            driver: ALL_OPTION
        }
    };
}

function normalizeClassificationValue(value) {
    const normalizedValue = String(value || '').trim();
    if (!normalizedValue) {
        return '';
    }
    return CLASSIFICATION_LABEL_MAP[normalizedValue.toUpperCase()] || normalizedValue;
}

function normalizeDriverValue(value) {
    const normalizedValue = String(value || '').trim();
    if (!normalizedValue) {
        return '';
    }
    return DRIVER_LABEL_MAP[normalizedValue.toUpperCase()] || normalizedValue;
}

function getAvailableFunctionId(rawFunction, index, sectionId, shopId) {
    return (
        rawFunction?.id ||
        rawFunction?.uniqueKey ||
        rawFunction?.adjustmentFunctionId ||
        rawFunction?.plantFunctionId ||
        `${sectionId}-${shopId}-function-${index + 1}`
    );
}

function buildRecordUrl(recordId) {
    return recordId ? `/${recordId}` : '';
}

function buildLightningRecordUrl(objectApiName, recordId, workspaceObjectApiName = '', workspaceRecordId = '') {
    if (!objectApiName || !recordId) {
        return '';
    }

    const baseUrl = `/lightning/r/${objectApiName}/${recordId}/view`;
    if (!workspaceObjectApiName || !workspaceRecordId) {
        return baseUrl;
    }

    const workspaceUrl = encodeURIComponent(`/lightning/r/${workspaceObjectApiName}/${workspaceRecordId}/view`);
    return `${baseUrl}?ws=${workspaceUrl}`;
}

function normalizeFunction(rawFunction, index, sectionId, shopId) {
    const id = getAvailableFunctionId(rawFunction, index, sectionId, shopId);
    const masterName =
        rawFunction?.masterName ||
        rawFunction?.plantFunctionMaster ||
        rawFunction?.plantFunctionName ||
        'Plant Function';
    const recordId = rawFunction?.recordId || rawFunction?.gwbFunctionId || '';

    return {
        id,
        uniqueKey: rawFunction?.uniqueKey || id,
        libraryId: rawFunction?.libraryId || rawFunction?.plantFunctionId || rawFunction?.recordId || id,
        adjustmentFunctionId: rawFunction?.adjustmentFunctionId || null,
        masterName,
        recordId,
        recordDisplayName:
            rawFunction?.plantFunctionRecordName ||
            (recordId ? rawFunction?.recordDisplayName || rawFunction?.gwbFunctionName || masterName : ''),
        plantProgram: rawFunction?.plantProgram || rawFunction?.plantProgramName || '',
        plantProgramCode: rawFunction?.plantProgramCode || '',
        plantProgramId: rawFunction?.plantProgramId || '',
        plantFunctionRecordName: rawFunction?.plantFunctionRecordName || '',
        plantFunctionMasterId: rawFunction?.plantFunctionMasterId || '',
        plantFunctionName: rawFunction?.plantFunctionName || '',
        plantFunctionLevel: rawFunction?.plantFunctionLevel || '',
        plantFunctionArea: rawFunction?.plantFunctionArea || '',
        line: rawFunction?.line || '',
        module: rawFunction?.module || '',
        plantFunctionId: rawFunction?.plantFunctionId || rawFunction?.recordId || '',
        gwbFunctionId: rawFunction?.gwbFunctionId || '',
        plantFunctionUrl: buildRecordUrl(rawFunction?.plantFunctionId || rawFunction?.recordId || ''),
        plantFunctionMasterUrl: buildLightningRecordUrl(
            'Function__c',
            rawFunction?.plantFunctionMasterId || '',
            'Plant_Function__c',
            rawFunction?.plantFunctionId || rawFunction?.recordId || ''
        ),
        gwbFunctionUrl: buildRecordUrl(rawFunction?.gwbFunctionId || rawFunction?.recordId || ''),
        plantProgramUrl: buildLightningRecordUrl(
            'Plant_Program__c',
            rawFunction?.plantProgramId || '',
            'Workbook__c',
            rawFunction?.gwbFunctionId || ''
        ),
        month: rawFunction?.month || '',
        year: rawFunction?.year ?? null,
        driver: rawFunction?.driver || '',
        classification: rawFunction?.classification || '',
        crew1: toFiniteNumber(rawFunction?.crew1, 0),
        crew2: toFiniteNumber(rawFunction?.crew2, 0),
        crew3: toFiniteNumber(rawFunction?.crew3, 0)
    };
}

function sumPlantFunctionCrews(functions = []) {
    return (functions || []).reduce(
        (sum, item) =>
            sum +
            Number(item?.crew1 || 0) +
            Number(item?.crew2 || 0) +
            Number(item?.crew3 || 0),
        0
    );
}

function normalizeShop(rawShop, index, sectionId) {
    const shopName = rawShop?.shopManagerView || `Shop ${index + 1}`;
    const id = rawShop?.id || rawShop?.uniqueKey || slugify(shopName);
    const rawFunctions = rawShop?.plantFunctions || rawShop?.functions || [];
    const functions = rawFunctions.map((item, itemIndex) =>
        normalizeFunction(item, itemIndex, sectionId, id)
    );
    const shopTarget = functions.length ? sumPlantFunctionCrews(functions) : Number(rawShop?.adjustment ?? 0);

    return {
        id,
        uniqueKey: rawShop?.uniqueKey || `${sectionId}-${shopName}`,
        adjustmentItemId: rawShop?.adjustmentItemId || null,
        shopName,
        shopManagerView: shopName,
        shopTarget,
        functions
    };
}

function normalizeSection(rawSection, index) {
    const year = String(rawSection?.year || '');
    const month = rawSection?.month || '';
    const sourceClassification = rawSection?.classification || '';
    const sourceDriver = rawSection?.driver || '';
    const classification = normalizeClassificationValue(sourceClassification);
    const driver = normalizeDriverValue(sourceDriver);
    const id =
        rawSection?.id ||
        rawSection?.uniqueKey ||
        `${slugify(year || `section-${index + 1}`)}-${slugify(month)}-${slugify(classification)}-${slugify(driver)}`;

    return {
        id,
        uniqueKey: rawSection?.uniqueKey || id,
        adjustmentId: rawSection?.adjustmentId || null,
        year,
        month,
        classification,
        driver,
        sourceClassification: sourceClassification || classification,
        sourceDriver: sourceDriver || driver,
        totalChangesNeeded: Number(rawSection?.totalChangesNeeded ?? 0),
        totalChangesMade: Number(rawSection?.totalChangesMade ?? 0),
        shops: (rawSection?.plantShops || []).map((shop, shopIndex) =>
            normalizeShop(shop, shopIndex, id)
        )
    };
}

function buildSectionLookupMaps(sections = []) {
    const sectionMap = new Map();
    const shopMap = new Map();
    const functionMap = new Map();

    sections.forEach((section) => {
        sectionMap.set(section.id, section);
        (section.shops || []).forEach((shop) => {
            shopMap.set(buildShopKey(section.id, shop.id), shop);
            (shop.functions || []).forEach((item) => {
                functionMap.set(`${buildShopKey(section.id, shop.id)}::${item.id}`, item);
            });
        });
    });

    return {
        sectionMap,
        shopMap,
        functionMap
    };
}

function parseResponse(rawResponse) {
    if (typeof rawResponse !== 'string') {
        return rawResponse || {};
    }

    try {
        return JSON.parse(rawResponse);
    } catch (error) {
        return {};
    }
}

function extractErrorMessages(error) {
    const messages = [];
    const body = error?.body;

    if (typeof error?.message === 'string' && error.message.trim()) {
        messages.push(error.message.trim());
    }

    if (typeof body?.message === 'string' && body.message.trim()) {
        messages.push(body.message.trim());
    }

    if (Array.isArray(body)) {
        body.forEach((item) => {
            if (typeof item?.message === 'string' && item.message.trim()) {
                messages.push(item.message.trim());
            }
        });
    }

    if (Array.isArray(body?.output?.errors)) {
        body.output.errors.forEach((item) => {
            if (typeof item?.message === 'string' && item.message.trim()) {
                messages.push(item.message.trim());
            }
        });
    }

    if (Array.isArray(body?.pageErrors)) {
        body.pageErrors.forEach((item) => {
            if (typeof item?.message === 'string' && item.message.trim()) {
                messages.push(item.message.trim());
            }
        });
    }

    Object.values(body?.fieldErrors || {}).forEach((fieldErrorList) => {
        (fieldErrorList || []).forEach((item) => {
            if (typeof item?.message === 'string' && item.message.trim()) {
                messages.push(item.message.trim());
            }
        });
    });

    return [...new Set(messages.filter(Boolean))];
}

function getSpecificErrorMessage(error, fallbackMessage) {
    const messages = extractErrorMessages(error);
    return messages.length ? messages.join(' | ') : fallbackMessage;
}

function toLogSafeValue(value) {
    try {
        return JSON.parse(JSON.stringify(value));
    } catch (error) {
        return value;
    }
}

function normalizeResponse(rawResponse, fallbackTarget = {}) {
    const source = parseResponse(rawResponse);
    const sections = source.plantPositionAdjustments || [];
    const target = source.target || {};
    const normalizedSections = sections.map((section, index) => normalizeSection(section, index)).sort(sectionSort);

    return {
        target: {
            id: target.id || fallbackTarget.recordId || null,
            name: target.name || fallbackTarget.targetName || '',
            regionName: target.regionName || fallbackTarget.regionName || '',
            plantName: target.plantName || fallbackTarget.plantName || '',
            scheduleLabel: target.scheduleLabel || fallbackTarget.scheduleLabel || '',
            status: target.status || fallbackTarget.initialStatus || ''
        },
        sections: normalizedSections
    };
}

function buildKnownFunctionMetadataMap(sections = []) {
    const metadataMap = new Map();

    sections.forEach((section) => {
        (section?.shops || []).forEach((shop) => {
            (shop?.functions || []).forEach((fn) => {
                const metadata = {
                    plantFunctionMasterId: fn?.plantFunctionMasterId || '',
                    plantProgramId: fn?.plantProgramId || '',
                    plantFunctionMaster: fn?.masterName || '',
                    plantProgramName: fn?.plantProgram || '',
                    plantProgramCode: fn?.plantProgramCode || '',
                    plantFunctionLevel: fn?.plantFunctionLevel || '',
                    plantFunctionArea: fn?.plantFunctionArea || '',
                    line: fn?.line || '',
                    module: fn?.module || ''
                };

                if (fn?.plantFunctionId) {
                    metadataMap.set(`pf:${fn.plantFunctionId}`, metadata);
                }
                if (fn?.gwbFunctionId) {
                    metadataMap.set(`gwb:${fn.gwbFunctionId}`, metadata);
                }
            });
        });
    });

    return metadataMap;
}

function mergeKnownFunctionMetadata(rawResponse, knownMetadataMap) {
    if (!rawResponse || !knownMetadataMap?.size) {
        return rawResponse;
    }

    const nextResponse = deepClone(rawResponse);
    const adjustments = nextResponse?.plantPositionAdjustments || [];

    adjustments.forEach((adjustment) => {
        (adjustment?.plantShops || []).forEach((shop) => {
            (shop?.plantFunctions || []).forEach((fn) => {
                const knownMetadata =
                    knownMetadataMap.get(`pf:${fn?.plantFunctionId || ''}`) ||
                    knownMetadataMap.get(`gwb:${fn?.gwbFunctionId || ''}`);

                if (!knownMetadata) {
                    return;
                }

                fn.plantFunctionMasterId = fn.plantFunctionMasterId || knownMetadata.plantFunctionMasterId;
                fn.plantProgramId = fn.plantProgramId || knownMetadata.plantProgramId;
                fn.plantFunctionMaster = fn.plantFunctionMaster || knownMetadata.plantFunctionMaster;
                fn.plantProgramName = fn.plantProgramName || knownMetadata.plantProgramName;
                fn.plantProgramCode = fn.plantProgramCode || knownMetadata.plantProgramCode;
                fn.plantFunctionLevel = fn.plantFunctionLevel || knownMetadata.plantFunctionLevel;
                fn.plantFunctionArea = fn.plantFunctionArea || knownMetadata.plantFunctionArea;
                fn.line = fn.line || knownMetadata.line;
                fn.module = fn.module || knownMetadata.module;
            });
        });
    });

    return nextResponse;
}

function buildPayloadAdjustment(section) {
    return {
        uniqueKey: section.uniqueKey || section.id,
        adjustmentId: section.adjustmentId,
        year: section.year,
        month: section.month,
        classification: section.sourceClassification || section.classification,
        driver: section.sourceDriver || section.driver,
        totalChangesNeeded: toFiniteNumber(section.totalChangesNeeded, 0),
        totalChangesMade: toFiniteNumber(
            (section.shops || []).reduce((sum, shop) => {
                if (!shop.functions?.length) {
                    return sum + toFiniteNumber(shop.shopTarget, 0);
                }
                return sum + shop.functions.reduce(
                    (functionSum, item) =>
                        functionSum +
                        toFiniteNumber(item.crew1, 0) +
                        toFiniteNumber(item.crew2, 0) +
                        toFiniteNumber(item.crew3, 0),
                    0
                );
            }, 0)
        ),
        plantShops: (section.shops || []).map((shop) => ({
            id: shop.id,
            uniqueKey: shop.uniqueKey || shop.id,
            adjustmentId: section.adjustmentId || null,
            adjustmentItemId: shop.adjustmentItemId || null,
            adjustment: toFiniteNumber(
                (shop.functions || []).length ? sumPlantFunctionCrews(shop.functions) : shop.shopTarget,
                0
            ),
            shopManagerView: shop.shopManagerView || shop.shopName,
            plantFunctions: (shop.functions || []).map((item) => ({
                month: item.month || section.month,
                year: item.year ?? toFiniteNumber(section.year, 0),
                driver: item.driver || section.sourceDriver || section.driver,
                classification: item.classification || section.sourceClassification || section.classification,
                crew1: toFiniteNumber(item.crew1, 0),
                crew2: toFiniteNumber(item.crew2, 0),
                crew3: toFiniteNumber(item.crew3, 0),
                plantFunctionId: item.plantFunctionId || item.recordId || '',
                gwbFunctionId: item.gwbFunctionId || ''
            }))
        }))
    };
}

function buildSavePayload(sections) {
    const normalizedSections = (sections || []).map((section) => buildPayloadAdjustment(section));

    return {
        plantPositionAdjustments: normalizedSections
    };
}

export default class GwbPlantPositionAdjustmentMaster extends NavigationMixin(LightningElement) {
    @api embedded = false;
    @api recordId;
    @api targetName = '';
    @api plantName = '';
    @api regionName = '';
    @api scheduleLabel = '';
    @api initialStatus = '';
    @api hasAdjustmentEditPermission = hasPlantAdminPermission || hasGwbSystemAdminPermission;
    @api hasAdjustmentCompletionPermission = hasGwbSystemAdminPermission;

    @track responseData = deepClone(EMPTY_RESPONSE);
    @track selectedMonth = ALL_OPTION;
    @track selectedClassification = ALL_OPTION;
    @track selectedDriver = ALL_OPTION;
    @track selectedBalanceStatus = ALL_OPTION;
    @track isEditMode = false;
    @track isExpandedTable = false;
    @track targetStatus = 'Published';
    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';
    @track completionValidationError = null;
    @track addFunctionsModalOpen = false;
    @track selectedShopContext = null;
    @track functionSearchTerm = '';
    @track selectedFunctionIds = [];
    @track modalRenderedFunctionCount = MODAL_FUNCTION_BATCH_SIZE;
    @track availablePlantFunctions = [];
    @track isLoadingPlantFunctions = false;
    @track expandedShopKeys = [];
    @track lastSavedSections = [];
    @track sessionBaselineSections = [];
    @track completionModalOpen = false;
    @track rowActionConfirmOpen = false;
    @track pendingRowAction = null;
    @track isFinalizing = false;
    @track isActionBusy = false;
    @track actionBusyLabel = '';
    globalFilters = null;
    @wire(EnclosingTabId) enclosingTabId;
    @wire(IsConsoleNavigation) isConsoleNavigation;
    @track renderedSectionCount = SECTION_BATCH_SIZE;
    @track isRenderingSections = false;
    lastSavedLookupMaps = buildSectionLookupMaps();
    sessionBaselineLookupMaps = buildSectionLookupMaps();
    draftShopValues = new Map();
    draftFunctionValues = new Map();
    monthOptionsCache = { sectionsRef: null, value: [] };
    classificationOptionsCache = { sectionsRef: null, month: null, value: [] };
    driverOptionsCache = { sectionsRef: null, month: null, classification: null, value: [] };
    filteredFunctionSourceCache = { search: null, value: [] };
    filteredAvailableFunctionsCache = {
        sourceRef: null,
        renderCount: null,
        selectedVersion: null,
        sectionId: null,
        shopId: null,
        value: []
    };
    filteredSectionsCache = {
        sectionsRef: null,
        month: null,
        classification: null,
        driver: null,
        balanceStatus: null,
        value: []
    };
    visibleSectionsCache = {
        filteredSectionsRef: null,
        renderedSectionCount: null,
        expandedKeysSignature: null,
        value: []
    };
    sectionViewCache = new Map();
    shopRowsCache = new Map();
    sectionWheelMode = null;
    sectionWheelModeResetHandle = null;
    selectedFunctionIdSet = new Set();
    selectedFunctionVersion = 0;

    logInfo(message, details) {
        if (details !== undefined) {
            // eslint-disable-next-line no-console
            console.info(`${COMPONENT_LOG_PREFIX} ${message}`, toLogSafeValue(details));
            return;
        }
        // eslint-disable-next-line no-console
        console.info(`${COMPONENT_LOG_PREFIX} ${message}`);
    }

    logWarn(message, details) {
        if (details !== undefined) {
            // eslint-disable-next-line no-console
            console.warn(`${COMPONENT_LOG_PREFIX} ${message}`, toLogSafeValue(details));
            return;
        }
        // eslint-disable-next-line no-console
        console.warn(`${COMPONENT_LOG_PREFIX} ${message}`);
    }

    logError(message, error, details) {
        const payload = {
            details: details ? toLogSafeValue(details) : undefined,
            errorMessages: extractErrorMessages(error),
            rawError: toLogSafeValue(error)
        };
        // eslint-disable-next-line no-console
        console.error(`${COMPONENT_LOG_PREFIX} ${message}`, payload);
    }

    async connectedCallback() {
        await this.loadAdjustmentAccess();
        await this.loadAdjustments();
        await this.loadGlobalFilters();
    }

    async loadAdjustmentAccess() {
        try {
            const access = await getAdjustmentAccess();
            if (typeof access?.hasAdjustmentEditPermission === 'boolean') {
                this.hasAdjustmentEditPermission = access.hasAdjustmentEditPermission;
            }
            if (typeof access?.hasAdjustmentCompletionPermission === 'boolean') {
                this.hasAdjustmentCompletionPermission = access.hasAdjustmentCompletionPermission;
            }
        } catch (error) {
            this.logWarn('Failed to load adjustment access. Falling back to client permission imports.', {
                recordId: this.recordId,
                message: getSpecificErrorMessage(
                    error,
                    `Unable to load adjustment access for target ${this.recordId}.`
                )
            });
        }
    }

    get monthOptions() {
        if (this.globalFilters?.months?.length) {
            return this.globalFilters.months.map((month) => ({
                label: month,
                value: month
            }));
        }
        if (this.monthOptionsCache.sectionsRef === this.responseData.sections) {
            return this.monthOptionsCache.value;
        }
        const months = new Set(this.responseData.sections.map((section) => section.month));
        const value = [ALL_OPTION, ...sortByOrder([...months], MONTH_ORDER)].map((month) => ({
            label: month,
            value: month
        }));
        this.monthOptionsCache = {
            sectionsRef: this.responseData.sections,
            value
        };
        return value;
    }

    get classificationOptions() {
        const filterMap = this.globalFilters?.classificationByMonth;
        if (filterMap) {
            const selectedValues =
                filterMap[this.selectedMonth] ||
                filterMap[ALL_OPTION] ||
                [ALL_OPTION];
            return selectedValues.map((classification) => ({
                label: classification,
                value: classification
            }));
        }
        if (
            this.classificationOptionsCache.sectionsRef === this.responseData.sections &&
            this.classificationOptionsCache.month === this.selectedMonth
        ) {
            return this.classificationOptionsCache.value;
        }
        const sections = this.responseData.sections.filter(
            (section) => this.selectedMonth === ALL_OPTION || section.month === this.selectedMonth
        );
        const values = [...new Set(sections.map((section) => section.classification))];
        const preferredOrder = this.globalFilters?.classifications?.length
            ? this.globalFilters.classifications.filter((value) => value !== ALL_OPTION)
            : CLASSIFICATION_ORDER;
        const value = [ALL_OPTION, ...sortByOrder(values, preferredOrder)].map((classification) => ({
            label: classification,
            value: classification
        }));
        this.classificationOptionsCache = {
            sectionsRef: this.responseData.sections,
            month: this.selectedMonth,
            value
        };
        return value;
    }

    get driverOptions() {
        const filterMap = this.globalFilters?.driverByClassification;
        if (filterMap) {
            const selectedValues = this.selectedClassification === ALL_OPTION
                ? this.globalFilters.drivers || [ALL_OPTION]
                : filterMap[this.selectedClassification] || [ALL_OPTION];
            return selectedValues.map((driver) => ({
                label: driver,
                value: driver
            }));
        }
        if (
            this.driverOptionsCache.sectionsRef === this.responseData.sections &&
            this.driverOptionsCache.month === this.selectedMonth &&
            this.driverOptionsCache.classification === this.selectedClassification
        ) {
            return this.driverOptionsCache.value;
        }
        const sections = this.responseData.sections.filter(
            (section) =>
                (this.selectedMonth === ALL_OPTION || section.month === this.selectedMonth) &&
                (this.selectedClassification === ALL_OPTION || section.classification === this.selectedClassification)
        );
        const values = [...new Set(sections.map((section) => section.driver))];
        const preferredOrder = this.globalFilters?.drivers?.length
            ? this.globalFilters.drivers.filter((value) => value !== ALL_OPTION)
            : DRIVER_ORDER;
        const value = [ALL_OPTION, ...sortByOrder(values, preferredOrder)].map((driver) => ({
            label: driver,
            value: driver
        }));
        this.driverOptionsCache = {
            sectionsRef: this.responseData.sections,
            month: this.selectedMonth,
            classification: this.selectedClassification,
            value
        };
        return value;
    }

    get showBalanceStatusFilter() {
        return ENABLE_BALANCE_STATUS_FILTER;
    }

    get balanceStatusOptions() {
        if (!this.showBalanceStatusFilter) {
            return [];
        }
        return [ALL_OPTION, MISMATCH_ONLY_OPTION].map((value) => ({
            label: value,
            value
        }));
    }

    get visibleSections() {
        const expandedKeysSignature = this.expandedShopKeys.join('|');
        if (
            this.visibleSectionsCache.filteredSectionsRef === this.filteredSections &&
            this.visibleSectionsCache.renderedSectionCount === this.renderedSectionCount &&
            this.visibleSectionsCache.expandedKeysSignature === expandedKeysSignature &&
            this.visibleSectionsCache.isEditMode === this.isEditMode &&
            this.visibleSectionsCache.lastSavedSectionsRef === this.lastSavedSections
        ) {
            return this.visibleSectionsCache.value;
        }

        const value = this.filteredSections
            .slice(0, this.renderedSectionCount)
            .map((section) => this.getRenderedSectionView(section));
        this.visibleSectionsCache = {
            filteredSectionsRef: this.filteredSections,
            renderedSectionCount: this.renderedSectionCount,
            expandedKeysSignature,
            isEditMode: this.isEditMode,
            lastSavedSectionsRef: this.lastSavedSections,
            value
        };
        return value;
    }

    get filteredSections() {
        if (
            this.filteredSectionsCache.sectionsRef === this.responseData.sections &&
            this.filteredSectionsCache.month === this.selectedMonth &&
            this.filteredSectionsCache.classification === this.selectedClassification &&
            this.filteredSectionsCache.driver === this.selectedDriver &&
            this.filteredSectionsCache.balanceStatus === this.selectedBalanceStatus
        ) {
            return this.filteredSectionsCache.value;
        }

        const value = this.responseData.sections.filter(
            (section) =>
                (this.selectedMonth === ALL_OPTION || section.month === this.selectedMonth) &&
                (this.selectedClassification === ALL_OPTION || section.classification === this.selectedClassification) &&
                (this.selectedDriver === ALL_OPTION || section.driver === this.selectedDriver) &&
                (!this.showBalanceStatusFilter ||
                    this.selectedBalanceStatus === ALL_OPTION ||
                    !this.isSectionBalanced(section))
        );

        this.filteredSectionsCache = {
            sectionsRef: this.responseData.sections,
            month: this.selectedMonth,
            classification: this.selectedClassification,
            driver: this.selectedDriver,
            balanceStatus: this.selectedBalanceStatus,
            value
        };

        return value;
    }

    get showFunctionColumns() {
        return this.visibleSections.some((section) =>
            section.shops.some((shop) => (shop.functions || []).length > 0)
        );
    }

    get showNoData() {
        return !this.isLoading && this.visibleSections.length === 0;
    }

    get hasMoreVisibleSections() {
        return this.filteredSections.length > this.renderedSectionCount;
    }

    get showRenderSpinner() {
        return this.isRenderingSections;
    }

    get isCompleted() {
        return this.targetStatus === 'Plant Complete';
    }

    get isLocked() {
        return this.targetStatus === 'Locked';
    }

    get targetStatusClass() {
        return this.isCompleted ? 'target-status target-status_complete' : 'target-status';
    }

    get showCompletionButton() {
        return this.targetStatus === 'Published';
    }

    get editButtonLabel() {
        return this.isEditMode ? 'Editing' : 'Edit Positions';
    }

    get expandButtonLabel() {
        return this.isExpandedTable ? 'Collapse Table' : 'Expand Table';
    }

    get showExpandAllButtons() {
        return this.showFunctionColumns;
    }

    get disableExpandAll() {
        const visibleExpandableShopKeys = this.getVisibleExpandableShopKeys();
        return !visibleExpandableShopKeys.length || visibleExpandableShopKeys.every((key) => this.expandedShopKeys.includes(key));
    }

    get disableCollapseAll() {
        const visibleExpandedShopKeys = this.getVisibleExpandedShopKeys();
        return !visibleExpandedShopKeys.length;
    }

    get completionButtonLabel() {
        return this.isCompleted ? 'Adjustments Completed' : 'Adjustments Completed';
    }

    get completionButtonDisabled() {
        return (
            !this.hasAdjustmentCompletionPermission ||
            this.isCompleted ||
            this.isLocked ||
            this.isInteractionBusy
        );
    }

    get editButtonDisabled() {
        return (
            !this.hasAdjustmentEditPermission ||
            this.isCompleted ||
            this.isLocked ||
            this.addFunctionsModalOpen ||
            this.isInteractionBusy
        );
    }

    get expandButtonDisabled() {
        return this.isEditMode || this.isInteractionBusy;
    }

    get tableContainerClass() {
        return this.isExpandedTable ? 'table-sections table-sections_expanded' : 'table-sections';
    }

    get adjustmentsCardClass() {
        return this.showFooterActions ? 'adjustments-card adjustments-card_editing' : 'adjustments-card';
    }

    get showFooterActions() {
        return this.isEditMode && !this.showNoData;
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Save';
    }

    get saveButtonDisabled() {
        return this.isInteractionBusy;
    }

    get cancelButtonDisabled() {
        return this.isInteractionBusy;
    }

    get isInteractionBusy() {
        return this.isLoading || this.isSaving || this.isFinalizing || this.isActionBusy;
    }

    get filterControlsDisabled() {
        return this.addFunctionsModalOpen || this.isInteractionBusy;
    }

    get showActionBusyOverlay() {
        return !this.isLoading && (this.isActionBusy || this.isSaving || this.isFinalizing);
    }

    get actionBusyOverlayLabel() {
        if (this.isSaving) {
            return 'Saving adjustments...';
        }
        if (this.isFinalizing) {
            return 'Finalizing adjustments...';
        }
        return this.actionBusyLabel || 'Updating adjustments...';
    }

    get modalTitle() {
        if (!this.selectedShopContext) {
            return 'Add Plant Functions';
        }
        return `Add Plant Functions to ${this.selectedShopContext.shopName}`;
    }

    get hasLoadError() {
        return Boolean(this.loadError);
    }

    get hasCompletionValidationError() {
        return Boolean(this.completionValidationError);
    }

    get hasPendingRowAction() {
        return this.rowActionConfirmOpen && Boolean(this.pendingRowAction);
    }

    get rowActionModalTitle() {
        switch (this.pendingRowAction?.action) {
            case 'zero-shop-functions':
                return 'Zero Out All Plant Functions';
            case 'remove-shop-functions':
                return 'Remove All Plant Functions';
            case 'zero-function-crews':
                return 'Zero Out All Crews';
            case 'reset-shop':
                return 'Reset Shop Target';
            case 'clear-shop':
                return 'Clear Shop Target';
            case 'reset-function':
                return 'Reset Plant Function';
            case 'clear-function':
                return 'Zero Out Plant Function';
            default:
                return 'Confirm Action';
        }
    }

    get rowActionModalQuestion() {
        switch (this.pendingRowAction?.action) {
            case 'zero-shop-functions':
                return 'Are you sure you want to zero out all Plant Functions for this Plant Shop?';
            case 'remove-shop-functions':
                return 'Are you sure you want to remove all Plant Functions from this Plant Shop?';
            case 'zero-function-crews':
                return 'Are you sure you want to zero out all crew values for this Plant Function?';
            case 'reset-shop':
                return 'Are you sure you want to reset this Shop Target to its earlier value?';
            case 'clear-shop':
                return 'Are you sure you want to clear this Shop Target?';
            case 'reset-function':
                return 'Are you sure you want to reset this Plant Function to its earlier values?';
            case 'clear-function':
                return 'Are you sure you want to zero out this Plant Function?';
            default:
                return 'Are you sure you want to continue?';
        }
    }

    get rowActionModalConfirmLabel() {
        switch (this.pendingRowAction?.action) {
            case 'remove-shop-functions':
                return 'Remove';
            case 'reset-shop':
            case 'reset-function':
                return 'Reset';
            case 'clear-shop':
                return 'Clear';
            default:
                return 'Zero Out';
        }
    }

    get showCompletionModal() {
        return this.completionModalOpen;
    }

    get filteredFunctionSource() {
        const search = (this.functionSearchTerm || '').trim().toLowerCase();
        if (this.filteredFunctionSourceCache.search === search) {
            return this.filteredFunctionSourceCache.value;
        }

        const value = this.availablePlantFunctions.filter((item) => {
            if (!search) {
                return true;
            }
            return [
                item?.plantFunctionMaster,
                item?.masterName,
                item?.plantFunctionLevel,
                item?.plantFunctionArea,
                item?.line,
                item?.module,
                item?.plantProgramCode,
                item?.recordId,
                item?.plantProgramName,
                item?.plantProgram
            ].some((fieldValue) => String(fieldValue || '').toLowerCase().includes(search));
        });

        this.filteredFunctionSourceCache = {
            search,
            value
        };
        return value;
    }

    get filteredAvailableFunctions() {
        const source = this.filteredFunctionSource;
        const sectionId = this.selectedShopContext?.sectionId || null;
        const shopId = this.selectedShopContext?.shopId || null;
        if (
            this.filteredAvailableFunctionsCache.sourceRef === source &&
            this.filteredAvailableFunctionsCache.renderCount === this.modalRenderedFunctionCount &&
            this.filteredAvailableFunctionsCache.selectedVersion === this.selectedFunctionVersion &&
            this.filteredAvailableFunctionsCache.sectionId === sectionId &&
            this.filteredAvailableFunctionsCache.shopId === shopId
        ) {
            return this.filteredAvailableFunctionsCache.value;
        }

        const selectedIds = this.selectedFunctionIdSet;
        const existingFunctionIds = this.getExistingFunctionIdsForShop(sectionId, shopId);
        const value = source.slice(0, this.modalRenderedFunctionCount).map((item, index) => {
            const normalizedItem = normalizeFunction(item, index, sectionId, shopId);
            const alreadyAdded =
                existingFunctionIds.has(normalizedItem.libraryId) ||
                existingFunctionIds.has(normalizedItem.plantFunctionId);
            return {
                ...normalizedItem,
                rowNumber: index + 1,
                checked: !alreadyAdded && selectedIds.has(normalizedItem.id),
                disabled: alreadyAdded,
                disabledReason: alreadyAdded ? 'Already added to this shop' : '',
                rowClass: alreadyAdded
                    ? 'picker-row picker-row_disabled'
                    : selectedIds.has(normalizedItem.id)
                        ? 'picker-row picker-row_selected'
                        : 'picker-row'
            };
        });

        this.filteredAvailableFunctionsCache = {
            sourceRef: source,
            renderCount: this.modalRenderedFunctionCount,
            selectedVersion: this.selectedFunctionVersion,
            sectionId,
            shopId,
            value
        };

        return value;
    }

    getExistingFunctionIdsForShop(sectionId, shopId) {
        if (!sectionId || !shopId) {
            return new Set();
        }

        const section = (this.responseData?.sections || []).find((item) => item.id === sectionId);
        const shop = (section?.shops || []).find((item) => item.id === shopId);
        const ids = new Set();

        (shop?.functions || []).forEach((item) => {
            [item?.libraryId, item?.plantFunctionId, item?.id]
                .filter(Boolean)
                .forEach((value) => ids.add(value));
        });

        return ids;
    }

    get disableAddFunctions() {
        return this.isLoadingPlantFunctions || this.selectedFunctionIdSet.size === 0;
    }

    get filteredAvailableFunctionCount() {
        return this.filteredFunctionSource.length;
    }

    get disablePlantFunctionAddAction() {
        return !this.hasAdjustmentEditPermission || this.isLocked || this.addFunctionsModalOpen || this.isInteractionBusy;
    }

    get showPlantFunctionModalLoading() {
        return this.isLoadingPlantFunctions;
    }

    get showPlantFunctionModalEmptyState() {
        return !this.isLoadingPlantFunctions && this.filteredAvailableFunctionCount === 0;
    }

    get disableRowActions() {
        return !this.hasAdjustmentEditPermission || this.isLocked || this.isInteractionBusy;
    }

    getSectionById(sectionId) {
        return (this.responseData.sections || []).find((section) => section.id === sectionId) || null;
    }

    async loadAdjustments() {
        this.isLoading = true;
        this.loadError = '';
        this.logInfo('Loading plant shop target adjustments.', { recordId: this.recordId });

        try {
            const rawResponse = await getPlantShopTargetAdjustments({ gwbYearId: this.recordId });
            this.applyResponseData(rawResponse);
            const response = parseResponse(rawResponse);
            this.logInfo('Loaded plant shop target adjustments.', {
                recordId: this.recordId,
                adjustmentCount: response?.plantPositionAdjustments?.length || 0
            });
        } catch (error) {
            this.loadError = getSpecificErrorMessage(
                error,
                `Unable to load plant shop target adjustments for target ${this.recordId}.`
            );
            this.logError('Failed to load plant shop target adjustments.', error, {
                recordId: this.recordId
            });
            this.applyResponseData(null);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Load Error',
                    message: this.loadError,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    async refreshAdjustmentsFromBackend({ preserveViewState = false } = {}) {
        const preservedFilters = preserveViewState
            ? {
                month: this.selectedMonth,
                classification: this.selectedClassification,
                driver: this.selectedDriver,
                balanceStatus: this.selectedBalanceStatus
            }
            : null;
        const preservedExpandedShopKeys = preserveViewState ? [...this.expandedShopKeys] : [];
        const knownFunctionMetadata = buildKnownFunctionMetadataMap(this.responseData.sections);
        const rawResponse = await getPlantShopTargetAdjustments({ gwbYearId: this.recordId });
        const hydratedResponse = mergeKnownFunctionMetadata(rawResponse, knownFunctionMetadata);
        this.applyResponseData(hydratedResponse);

        if (preserveViewState && preservedFilters) {
            this.selectedMonth = preservedFilters.month;
            this.selectedClassification = preservedFilters.classification;
            this.selectedDriver = preservedFilters.driver;
            this.selectedBalanceStatus = preservedFilters.balanceStatus;
            this.expandedShopKeys = preservedExpandedShopKeys;
            this.resetRenderedSectionWindow();
        }

        return hydratedResponse;
    }

    async loadGlobalFilters() {
        this.logInfo('Loading global filters.', { recordId: this.recordId });
        try {
            const rawFilters = await getGlobalFilters({ gwbYearId: this.recordId });
            const normalizedFilters = normalizeGlobalFilters(rawFilters);
            this.globalFilters = normalizedFilters;
            this.logInfo('Loaded global filters.', {
                recordId: this.recordId,
                months: normalizedFilters.months,
                defaults: normalizedFilters.defaults
            });
            this.resetFilters();
        } catch (error) {
            this.globalFilters = null;
            this.logWarn('Failed to load global filters. Falling back to locally derived filters.', {
                recordId: this.recordId,
                message: getSpecificErrorMessage(
                    error,
                    `Unable to load global filters for target ${this.recordId}.`
                )
            });
        }
    }

    applyResponseData(response) {
        const normalizedResponse = normalizeResponse(response, {
            recordId: this.recordId,
            targetName: this.targetName,
            plantName: this.plantName,
            regionName: this.regionName,
            scheduleLabel: this.scheduleLabel,
            initialStatus: this.initialStatus
        });

        this.responseData = normalizedResponse;
        this.targetStatus = this.initialStatus || normalizedResponse.target.status || this.targetStatus;
        this.targetName = normalizedResponse.target.name || this.targetName;
        this.plantName = normalizedResponse.target.plantName || this.plantName;
        this.regionName = normalizedResponse.target.regionName || this.regionName;
        this.scheduleLabel = normalizedResponse.target.scheduleLabel || this.scheduleLabel;
        this.lastSavedSections = deepClone(normalizedResponse.sections);
        this.sessionBaselineSections = deepClone(normalizedResponse.sections);
        this.lastSavedLookupMaps = buildSectionLookupMaps(this.lastSavedSections);
        this.sessionBaselineLookupMaps = buildSectionLookupMaps(this.sessionBaselineSections);
        this.expandedShopKeys = [];
        this.filteredSectionsCache = {
            sectionsRef: null,
            month: null,
            classification: null,
            driver: null,
            balanceStatus: null,
            value: []
        };
        this.visibleSectionsCache = {
            filteredSectionsRef: null,
            renderedSectionCount: null,
            expandedKeysSignature: null,
            value: []
        };
        this.sectionViewCache.clear();
        this.shopRowsCache.clear();
        this.resetFilters();
    }

    async handleFiltersChange(event) {
        const {
            month,
            classification,
            driver,
            balanceStatus = this.selectedBalanceStatus
        } = event.detail;
        if (
            month === this.selectedMonth &&
            classification === this.selectedClassification &&
            driver === this.selectedDriver &&
            balanceStatus === this.selectedBalanceStatus
        ) {
            return;
        }

        await this.runBusyTransition('Applying filters...', () => {
            this.flushDraftValuesToState();
            this.selectedMonth = month;
            this.selectedClassification = classification;
            this.selectedDriver = driver;
            this.selectedBalanceStatus = balanceStatus;
            this.resetRenderedSectionWindow();
        });
    }

    async handleResetFilters() {
        await this.runBusyTransition('Resetting filters...', () => {
            this.flushDraftValuesToState();
            this.resetFilters();
        });
    }

    async handleRecordLinkClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget?.dataset?.recordId;
        const objectApiName = event.currentTarget?.dataset?.objectApiName;
        if (!recordId || !objectApiName) {
            return;
        }

        const pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        };

        if (this.isConsoleNavigation?.data === true) {
            try {
                const parentTabId = this.enclosingTabId?.data;
                if (parentTabId) {
                    await openSubtab(parentTabId, {
                        pageReference,
                        focus: true
                    });
                    return;
                }
            } catch (error) {
                this.logWarn('Workspace subtab navigation failed. Falling back to standard navigation.', {
                    recordId,
                    objectApiName,
                    message: error?.message || 'Unknown workspace navigation error'
                });
            }
        }

        this[NavigationMixin.Navigate](pageReference, false);
    }

    async handleToggleEditMode() {
        if (!this.hasAdjustmentEditPermission || this.isCompleted || this.isLocked || this.isInteractionBusy) {
            return;
        }
        await this.runBusyTransition('Opening edit mode...', () => {
            this.isEditMode = true;
            this.isExpandedTable = false;
        });
    }

    async handleCancelEdit() {
        if (this.isSaving) {
            return;
        }
        this.isEditMode = false;
        await this.waitForUiTick();
        this.responseData = {
            ...this.responseData,
            sections: deepClone(this.lastSavedSections)
        };
        this.filteredSectionsCache = {
            sectionsRef: null,
            month: null,
            classification: null,
            driver: null,
            balanceStatus: null,
            value: []
        };
        this.visibleSectionsCache = {
            filteredSectionsRef: null,
            renderedSectionCount: null,
            expandedKeysSignature: null,
            value: []
        };
        this.sectionViewCache.clear();
        this.shopRowsCache.clear();
        this.clearDraftValues();
    }

    async handleSaveAdjustments() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        try {
            this.flushDraftValuesToState();
            const dirtySections = this.getDirtySections();
            if (!dirtySections.length) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'No Changes',
                        message: 'There are no adjustment changes to save.',
                        variant: 'info'
                    })
                );
                return;
            }
            const payload = buildSavePayload(dirtySections);
            payload.gwbYearId = this.recordId;
            this.logInfo('Saving plant shop target adjustments.', {
                recordId: this.recordId,
                adjustmentCount: payload?.plantPositionAdjustments?.length || 0,
                totalSectionCount: this.responseData.sections?.length || 0
            });
            const result = await updatePlantShopTargetAdjustments({
                payload
            });
            this.logInfo('Saved plant shop target adjustments.', {
                recordId: this.recordId,
                plantPositionAdjustmentCount: result?.plantPositionAdjustmentCount,
                plantShopCount: result?.plantShopCount,
                message: result?.message
            });

            await this.refreshAdjustmentsFromBackend({ preserveViewState: true });
            this.isEditMode = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Draft Saved',
                    message: 'Plant shop target adjustments were saved successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            const message = getSpecificErrorMessage(
                error,
                `Unable to save plant shop target adjustments for target ${this.recordId}.`
            );
            this.logError('Failed to save plant shop target adjustments.', error, {
                recordId: this.recordId
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    async handleToggleExpandedTable() {
        if (this.isEditMode || this.isInteractionBusy) {
            return;
        }
        await this.runBusyTransition(
            this.isExpandedTable ? 'Collapsing table...' : 'Expanding table...',
            () => {
                this.isExpandedTable = !this.isExpandedTable;
            }
        );
    }

    handleTableScroll(event) {
        if (this.isRenderingSections || !this.hasMoreVisibleSections) {
            return;
        }

        const target = event.target;
        if (target.scrollTop + target.clientHeight >= target.scrollHeight - LOAD_MORE_SCROLL_OFFSET) {
            this.loadNextSectionBatch();
        }
    }

    setSectionWheelMode(mode) {
        this.sectionWheelMode = mode;
        if (this.sectionWheelModeResetHandle) {
            clearTimeout(this.sectionWheelModeResetHandle);
        }
        this.sectionWheelModeResetHandle = setTimeout(() => {
            this.sectionWheelMode = null;
            this.sectionWheelModeResetHandle = null;
        }, 320);
    }

    scrollOuterTableBy(deltaY) {
        const outerScroller = this.template.querySelector('.table-sections');
        if (!outerScroller) {
            return false;
        }
        const previousScrollTop = outerScroller.scrollTop;
        outerScroller.scrollTop += deltaY;
        return Math.abs(outerScroller.scrollTop - previousScrollTop) > 0;
    }

    handleSectionHeaderWheel(event) {
        if (!this.scrollOuterTableBy(event.deltaY)) {
            return;
        }

        event.preventDefault();
        event.stopPropagation();
        this.setSectionWheelMode('outer');
    }

    handleSectionBodyWheel(event) {
        const isItemArea = Boolean(event.target.closest('tbody'));
        const bodyScroller = event.currentTarget;
        const canScrollUp = bodyScroller.scrollTop > 0;
        const canScrollDown =
            bodyScroller.scrollTop + bodyScroller.clientHeight < bodyScroller.scrollHeight - 1;
        const isTryingToScrollUp = event.deltaY < 0;
        const isTryingToScrollDown = event.deltaY > 0;
        const innerCanContinue =
            (isTryingToScrollUp && canScrollUp) ||
            (isTryingToScrollDown && canScrollDown);

        if (this.sectionWheelMode === 'outer') {
            if (!this.scrollOuterTableBy(event.deltaY)) {
                return;
            }
            event.preventDefault();
            event.stopPropagation();
            this.setSectionWheelMode('outer');
            return;
        }

        if (!isItemArea) {
            if (!this.scrollOuterTableBy(event.deltaY)) {
                return;
            }
            event.preventDefault();
            event.stopPropagation();
            this.setSectionWheelMode('outer');
            return;
        }

        if (innerCanContinue) {
            event.stopPropagation();
            this.setSectionWheelMode('inner');
            return;
        }

        if (!this.scrollOuterTableBy(event.deltaY)) {
            return;
        }

        event.preventDefault();
        event.stopPropagation();
        this.setSectionWheelMode('outer');
    }

    async handleExpandAll() {
        if (this.isInteractionBusy) {
            return;
        }
        await this.runBusyTransition('Expanding shops...', () => {
            const visibleExpandableShopKeys = this.getVisibleExpandableShopKeys();
            this.expandedShopKeys = [...new Set([...this.expandedShopKeys, ...visibleExpandableShopKeys])];
        });
    }

    async handleCollapseAll() {
        if (this.isInteractionBusy) {
            return;
        }
        await this.runBusyTransition('Collapsing shops...', () => {
            const visibleExpandableShopKeys = new Set(this.getVisibleExpandableShopKeys());
            this.expandedShopKeys = this.expandedShopKeys.filter((key) => !visibleExpandableShopKeys.has(key));
        });
    }

    async handleToggleShop(event) {
        const { sectionId, shopId } = event.currentTarget.dataset;
        const key = buildShopKey(sectionId, shopId);
        const isExpanded = this.expandedShopKeys.includes(key);
        await this.runBusyTransition(isExpanded ? 'Collapsing shop...' : 'Expanding shop...', () => {
            this.expandedShopKeys = isExpanded
                ? this.expandedShopKeys.filter((item) => item !== key)
                : [...this.expandedShopKeys, key];
        });
    }

    async handleOpenAddFunctionsModal(event) {
        if (this.disablePlantFunctionAddAction) {
            return;
        }
        const { sectionId, shopId, shopName } = event.currentTarget.dataset;
        const selectedSection = this.getSectionById(sectionId);
        const classification = selectedSection?.sourceClassification || selectedSection?.classification || '';
        this.isActionBusy = true;
        this.actionBusyLabel = 'Opening plant functions...';
        await this.waitForUiTick();
        this.selectedShopContext = { sectionId, shopId, shopName, classification };
        this.addFunctionsModalOpen = true;
        this.functionSearchTerm = '';
        this.modalRenderedFunctionCount = MODAL_FUNCTION_BATCH_SIZE;
        this.selectedFunctionIdSet = new Set();
        this.selectedFunctionVersion = 0;
        this.selectedFunctionIds = [];
        this.availablePlantFunctions = [];
        this.isLoadingPlantFunctions = true;
        this.filteredFunctionSourceCache = { search: null, value: [] };
        this.filteredAvailableFunctionsCache = {
            sourceRef: null,
            renderCount: null,
            selectedVersion: null,
            sectionId: null,
            shopId: null,
            value: []
        };
        await this.waitForUiTick();
        this.isActionBusy = false;
        this.actionBusyLabel = '';

        try {
            const rawFunctions = await getTargetPlantFunctionList({
                gwbYearId: this.recordId,
                shopManagerView: shopName,
                classification
            });
            this.availablePlantFunctions = rawFunctions || [];
            this.filteredFunctionSourceCache = { search: null, value: [] };
            this.filteredAvailableFunctionsCache = {
                sourceRef: null,
                renderCount: null,
                selectedVersion: null,
                sectionId: null,
                shopId: null,
                value: []
            };
        } catch (error) {
            const message = getSpecificErrorMessage(
                error,
                `Unable to load plant functions for ${shopName}.`
            );
            this.logError('Failed to load plant functions.', error, {
                recordId: this.recordId,
                shopManagerView: shopName,
                classification
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Plant Functions Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoadingPlantFunctions = false;
        }
    }

    handleCloseAddFunctionsModal() {
        this.addFunctionsModalOpen = false;
        this.selectedShopContext = null;
        this.functionSearchTerm = '';
        this.modalRenderedFunctionCount = MODAL_FUNCTION_BATCH_SIZE;
        this.selectedFunctionIdSet = new Set();
        this.selectedFunctionVersion = 0;
        this.selectedFunctionIds = [];
        this.availablePlantFunctions = [];
        this.isLoadingPlantFunctions = false;
        this.filteredFunctionSourceCache = { search: null, value: [] };
        this.filteredAvailableFunctionsCache = {
            sourceRef: null,
            renderCount: null,
            selectedVersion: null,
            sectionId: null,
            shopId: null,
            value: []
        };
    }

    handleFunctionSearch(event) {
        this.functionSearchTerm = event.target.value || '';
        this.modalRenderedFunctionCount = MODAL_FUNCTION_BATCH_SIZE;
        this.filteredAvailableFunctionsCache = {
            sourceRef: null,
            renderCount: null,
            selectedVersion: null,
            sectionId: null,
            shopId: null,
            value: []
        };
    }

    handleToggleAvailableFunction(event) {
        const functionId = event.target.dataset.functionId;
        if (event.target.checked) {
            const nextSelectedIds = new Set(this.selectedFunctionIdSet);
            nextSelectedIds.add(functionId);
            this.selectedFunctionIdSet = nextSelectedIds;
            this.selectedFunctionIds = [...nextSelectedIds];
            this.selectedFunctionVersion += 1;
            return;
        }
        const nextSelectedIds = new Set(this.selectedFunctionIdSet);
        nextSelectedIds.delete(functionId);
        this.selectedFunctionIdSet = nextSelectedIds;
        this.selectedFunctionIds = [...nextSelectedIds];
        this.selectedFunctionVersion += 1;
    }

    handleModalTableScroll(event) {
        const target = event.target;
        if (
            target.scrollTop + target.clientHeight < target.scrollHeight - MODAL_FUNCTION_LOAD_MORE_OFFSET ||
            this.modalRenderedFunctionCount >= this.filteredAvailableFunctionCount
        ) {
            return;
        }

        this.modalRenderedFunctionCount = Math.min(
            this.modalRenderedFunctionCount + MODAL_FUNCTION_BATCH_SIZE,
            this.filteredAvailableFunctionCount
        );
    }

    async handleAddSelectedFunctions() {
        if (!this.selectedShopContext || !this.selectedFunctionIdSet.size) {
            return;
        }
        await this.runBusyTransition('Adding plant functions...', () => {
            this.isEditMode = true;
            const selectedFunctions = this.availablePlantFunctions
                .filter((item, index) =>
                    this.selectedFunctionIdSet.has(
                        getAvailableFunctionId(
                            item,
                            index,
                            this.selectedShopContext.sectionId,
                            this.selectedShopContext.shopId
                        )
                    )
                )
                .map((item, index) =>
                    normalizeFunction(
                        item,
                        index,
                        this.selectedShopContext.sectionId,
                        this.selectedShopContext.shopId
                    )
                );
            this.responseData = {
                ...this.responseData,
                sections: this.responseData.sections.map((section) => {
                    if (section.id !== this.selectedShopContext.sectionId) {
                        return section;
                    }
                    return {
                        ...section,
                        shops: section.shops.map((shop) => {
                            if (shop.id !== this.selectedShopContext.shopId) {
                                return shop;
                            }
                            const existingIds = new Set(shop.functions.map((item) => item.libraryId));
                            const newFunctions = selectedFunctions
                                .filter((item) => !existingIds.has(item.libraryId))
                                .map((item) => ({
                                    id: `${section.id}-${shop.id}-${item.id}`,
                                    libraryId: item.plantFunctionId || item.recordId || item.id,
                                    adjustmentFunctionId: null,
                                    masterName: item.masterName,
                                    recordId: item.recordId,
                                    plantProgram: item.plantProgram,
                                    plantProgramCode: item.plantProgramCode,
                                    plantProgramId: item.plantProgramId,
                                    plantFunctionMasterId: item.plantFunctionMasterId,
                                    plantFunctionLevel: item.plantFunctionLevel,
                                    plantFunctionArea: item.plantFunctionArea,
                                    line: item.line,
                                    module: item.module,
                                    plantFunctionId: item.plantFunctionId || item.recordId || '',
                                    gwbFunctionId: '',
                                    plantFunctionUrl: item.plantFunctionUrl,
                                    plantFunctionMasterUrl: item.plantFunctionMasterUrl,
                                    gwbFunctionUrl: '',
                                    plantProgramUrl: item.plantProgramUrl,
                                    month: section.month,
                                    year: Number(section.year || 0),
                                    driver: section.sourceDriver || section.driver,
                                    classification: section.sourceClassification || section.classification,
                                    crew1: 0,
                                    crew2: 0,
                                    crew3: 0
                                }));
                            const nextFunctions = [...shop.functions, ...newFunctions];
                            return {
                                ...shop,
                                shopTarget: sumPlantFunctionCrews(nextFunctions),
                                functions: nextFunctions
                            };
                        })
                    };
                })
            };

            const expandedKey = buildShopKey(this.selectedShopContext.sectionId, this.selectedShopContext.shopId);
            if (!this.expandedShopKeys.includes(expandedKey)) {
                this.expandedShopKeys = [...this.expandedShopKeys, expandedKey];
            }

            this.handleCloseAddFunctionsModal();
        });
        this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Plant Functions Added',
                    message: 'Plant functions were added to the selected shop target.',
                    variant: 'success'
                })
            );
    }

    handleDraftValueInput(event) {
        const { sectionId, shopId, functionId, field } = event.target.dataset;
        const rawValue = event.target.value;
        if (functionId) {
            this.draftFunctionValues.set(
                buildFunctionFieldKey(sectionId, shopId, functionId, field),
                rawValue
            );
            if (rawValue !== '' && rawValue !== '-') {
                this.refreshDerivedRows();
            }
            return;
        }
        this.draftShopValues.set(buildShopKey(sectionId, shopId), rawValue);
    }

    handleCrewValueChange(event) {
        this.clearCompletionValidationError();
        const { sectionId, shopId, functionId, field } = event.target.dataset;
        const fieldKey = buildFunctionFieldKey(sectionId, shopId, functionId, field);
        const nextValue = toFiniteNumber(
            this.draftFunctionValues.has(fieldKey)
                ? this.draftFunctionValues.get(fieldKey)
                : event.target.value,
            0
        );
        this.draftFunctionValues.delete(fieldKey);
        this.updateFunctionState(sectionId, shopId, functionId, (item) => ({
            ...item,
            [field]: nextValue
        }));
    }

    handleShopTargetChange(event) {
        this.clearCompletionValidationError();
        const { sectionId, shopId } = event.target.dataset;
        const currentShop = this.findCurrentShop(sectionId, shopId);
        if (currentShop?.functions?.length) {
            this.draftShopValues.delete(buildShopKey(sectionId, shopId));
            return;
        }
        const shopKey = buildShopKey(sectionId, shopId);
        const nextValue = toFiniteNumber(
            this.draftShopValues.has(shopKey)
                ? this.draftShopValues.get(shopKey)
                : event.target.value,
            0
        );
        this.draftShopValues.delete(shopKey);
        this.updateShopState(sectionId, shopId, (shop) => ({
            ...shop,
            shopTarget: nextValue
        }));
    }

    handleNumberInputWheel(event) {
        event.preventDefault();
        event.target.blur();
    }

    handleRowMenuSelect(event) {
        if (this.disableRowActions) {
            return;
        }
        const { sectionId, shopId, functionId } = event.currentTarget.dataset;
        const action = event.detail.value;
        this.pendingRowAction = {
            action,
            sectionId,
            shopId,
            functionId: functionId || null
        };
        this.rowActionConfirmOpen = true;
    }

    async handleOpenCompletionModal() {
        if (this.completionButtonDisabled) {
            return;
        }
        await this.runBusyTransition('Checking adjustment totals...', () => {
        this.flushDraftValuesToState();
        const unbalancedSection = this.responseData.sections.find(
            (section) => this.calculateSectionTotal(section) !== section.totalChangesNeeded
        );

        if (unbalancedSection) {
            this.logWarn('Completion blocked because monthly adjustment totals are unbalanced.', {
                recordId: this.recordId,
                sectionId: unbalancedSection.id,
                month: unbalancedSection.month,
                classification: unbalancedSection.classification,
                driver: unbalancedSection.driver
            });
            this.completionValidationError = {
                title: 'Mismatched monthly adjustment totals.',
                message: 'Ensure amounts for Changes Needed and Changes Made match for all months to complete adjustments.'
            };
            return;
        }

        this.clearCompletionValidationError();
        this.completionModalOpen = true;
        });
    }

    handleCloseCompletionModal() {
        if (this.isFinalizing) {
            return;
        }
        this.completionModalOpen = false;
    }

    async handleConfirmCompletion() {
        if (this.completionButtonDisabled) {
            return;
        }
        this.isFinalizing = true;
        this.logInfo('Finalizing plant shop target adjustments.', { recordId: this.recordId });

        try {
            await finalizeTarget({ gwbYearId: this.recordId });
            await this.refreshAdjustmentsFromBackend({ preserveViewState: false });
            this.logInfo('Finalized plant shop target adjustments.', { recordId: this.recordId });
            this.clearCompletionValidationError();
            this.targetStatus = 'Locked';
            this.isEditMode = false;
            this.completionModalOpen = false;
            this.dispatchEvent(
                new CustomEvent('statuschange', {
                    detail: {
                        status: 'Locked'
                    }
                })
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Adjustments Completed',
                    message: 'The target is now locked and no longer allows position edits.',
                    variant: 'success'
                })
            );
        } catch (error) {
            const message = getSpecificErrorMessage(
                error,
                `Unable to finalize target adjustments for target ${this.recordId}.`
            );
            this.logError('Failed to finalize plant shop target adjustments.', error, {
                recordId: this.recordId
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Completion Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isFinalizing = false;
        }
    }

    handleDismissCompletionValidationError() {
        this.clearCompletionValidationError();
    }

    handleCloseRowActionConfirm() {
        this.rowActionConfirmOpen = false;
        this.pendingRowAction = null;
    }

    handleConfirmRowAction() {
        const actionContext = this.pendingRowAction;
        if (!actionContext) {
            return;
        }

        if (
            !this.isEditMode &&
            ['zero-shop-functions', 'zero-function-crews', 'clear-function', 'reset-shop', 'clear-shop', 'reset-function'].includes(
                actionContext.action
            )
        ) {
            this.isEditMode = true;
        }

        this.executeRowAction(actionContext);
        this.handleCloseRowActionConfirm();
    }

    clearShopTarget(sectionId, shopId) {
        this.draftShopValues.delete(buildShopKey(sectionId, shopId));
        this.updateShopState(sectionId, shopId, (shop) => ({
            ...shop,
            shopTarget: 0
        }));
    }

    resetShopTargetToSessionBaseline(sectionId, shopId) {
        this.clearCompletionValidationError();
        const baselineShop = this.findSessionBaselineShop(sectionId, shopId);
        if (!baselineShop) {
            return;
        }
        this.draftShopValues.delete(buildShopKey(sectionId, shopId));
        this.updateShopState(sectionId, shopId, (shop) => ({
            ...shop,
            shopTarget: Number(baselineShop.shopTarget || 0)
        }));
    }

    clearFunctionValues(sectionId, shopId, functionId) {
        this.clearCompletionValidationError();
        this.clearDraftFunctionValues(sectionId, shopId, functionId);
        this.updateFunctionState(sectionId, shopId, functionId, (item) => ({
            ...item,
            crew1: 0,
            crew2: 0,
            crew3: 0
        }));
    }

    resetFunctionValuesToSessionBaseline(sectionId, shopId, functionId) {
        this.clearCompletionValidationError();
        const baselineFunction = this.findSessionBaselineFunction(sectionId, shopId, functionId);
        if (!baselineFunction) {
            return;
        }
        this.clearDraftFunctionValues(sectionId, shopId, functionId);
        this.updateFunctionState(sectionId, shopId, functionId, (item) => ({
            ...item,
            crew1: Number(baselineFunction.crew1 || 0),
            crew2: Number(baselineFunction.crew2 || 0),
            crew3: Number(baselineFunction.crew3 || 0)
        }));
    }

    zeroOutShopFunctions(sectionId, shopId) {
        this.clearCompletionValidationError();
        const shop = this.findCurrentShop(sectionId, shopId);
        if (!shop?.functions?.length) {
            return;
        }
        shop.functions.forEach((item) => {
            this.clearDraftFunctionValues(sectionId, shopId, item.id);
        });
        this.updateShopState(sectionId, shopId, (currentShop) => ({
            ...currentShop,
            shopTarget: 0,
            functions: currentShop.functions.map((item) => ({
                ...item,
                crew1: 0,
                crew2: 0,
                crew3: 0
            }))
        }));
    }

    removeAllShopFunctions(sectionId, shopId) {
        this.clearCompletionValidationError();
        const shop = this.findCurrentShop(sectionId, shopId);
        if (!shop) {
            return;
        }
        shop.functions.forEach((item) => {
            this.clearDraftFunctionValues(sectionId, shopId, item.id);
        });
        this.updateShopState(sectionId, shopId, (currentShop) => ({
            ...currentShop,
            shopTarget: 0,
            functions: []
        }));
        const expandedKey = buildShopKey(sectionId, shopId);
        this.expandedShopKeys = this.expandedShopKeys.filter((key) => key !== expandedKey);
    }

    executeRowAction(actionContext) {
        const { action, sectionId, shopId, functionId } = actionContext;
        switch (action) {
            case 'zero-shop-functions':
                this.zeroOutShopFunctions(sectionId, shopId);
                return;
            case 'remove-shop-functions':
                this.removeAllShopFunctions(sectionId, shopId);
                return;
            case 'zero-function-crews':
            case 'clear-function':
                this.clearFunctionValues(sectionId, shopId, functionId);
                return;
            case 'reset-shop':
                this.resetShopTargetToSessionBaseline(sectionId, shopId);
                return;
            case 'clear-shop':
                this.clearShopTarget(sectionId, shopId);
                return;
            case 'reset-function':
                this.resetFunctionValuesToSessionBaseline(sectionId, shopId, functionId);
                return;
            default:
        }
    }

    resetFilters() {
        const fallbackDefaults = getDefaultFilterValues(this.responseData.sections);
        const defaults = {
            month: this.globalFilters?.defaults?.month || fallbackDefaults.month,
            classification: this.globalFilters?.defaults?.classification || fallbackDefaults.classification,
            driver: this.globalFilters?.defaults?.driver || fallbackDefaults.driver
        };
        this.selectedMonth = defaults.month;
        this.selectedClassification = defaults.classification;
        this.selectedDriver = defaults.driver;
        this.selectedBalanceStatus = ALL_OPTION;
        this.resetRenderedSectionWindow();
    }

    resetRenderedSectionWindow() {
        this.renderedSectionCount = SECTION_BATCH_SIZE;
        this.showSectionRenderSpinnerForTick();
    }

    loadNextSectionBatch() {
        if (!this.hasMoreVisibleSections) {
            return;
        }

        this.isRenderingSections = true;
        this.afterNextPaint(() => {
            this.renderedSectionCount = Math.min(
                this.renderedSectionCount + SECTION_BATCH_SIZE,
                this.filteredSections.length
            );
            this.isRenderingSections = false;
        });
    }

    showSectionRenderSpinnerForTick() {
        this.isRenderingSections = true;
        this.afterNextPaint(() => {
            this.isRenderingSections = false;
        });
    }

    refreshDerivedRows() {
        this.visibleSectionsCache = {
            filteredSectionsRef: null,
            renderedSectionCount: null,
            expandedKeysSignature: null,
            value: []
        };
        this.sectionViewCache.clear();
        this.shopRowsCache.clear();
        this.responseData = {
            ...this.responseData
        };
    }

    waitForNextPaint() {
        return new Promise((resolve) => {
            this.afterNextPaint(resolve);
        });
    }

    waitForUiTick() {
        return Promise.resolve();
    }

    clearDraftValues() {
        this.draftShopValues.clear();
        this.draftFunctionValues.clear();
    }

    clearDraftFunctionValues(sectionId, shopId, functionId) {
        ['crew1', 'crew2', 'crew3'].forEach((field) => {
            this.draftFunctionValues.delete(buildFunctionFieldKey(sectionId, shopId, functionId, field));
        });
    }

    getShopTargetValue(sectionId, shop) {
        const key = buildShopKey(sectionId, shop.id);
        if (this.draftShopValues.has(key)) {
            return toFiniteNumber(this.draftShopValues.get(key), 0);
        }
        return toFiniteNumber(shop.shopTarget, 0);
    }

    getFunctionFieldValue(sectionId, shopId, item, field) {
        const key = buildFunctionFieldKey(sectionId, shopId, item.id, field);
        if (this.draftFunctionValues.has(key)) {
            return toFiniteNumber(this.draftFunctionValues.get(key), 0);
        }
        return toFiniteNumber(item[field], 0);
    }

    flushDraftValuesToState() {
        if (!this.draftShopValues.size && !this.draftFunctionValues.size) {
            return;
        }

        const nextSections = this.responseData.sections.map((section) => {
            let sectionChanged = false;
            const nextShops = section.shops.map((shop) => {
                let shopChanged = false;
                const shopKey = buildShopKey(section.id, shop.id);
                let nextShop = shop;

                if (this.draftShopValues.has(shopKey)) {
                    nextShop = {
                        ...nextShop,
                        shopTarget: toFiniteNumber(this.draftShopValues.get(shopKey), 0)
                    };
                    shopChanged = true;
                }

                if (shop.functions.length) {
                    const nextFunctions = shop.functions.map((item) => {
                        let nextItem = item;
                        ['crew1', 'crew2', 'crew3'].forEach((field) => {
                            const key = buildFunctionFieldKey(section.id, shop.id, item.id, field);
                            if (this.draftFunctionValues.has(key)) {
                                if (nextItem === item) {
                                    nextItem = { ...item };
                                }
                                nextItem[field] = toFiniteNumber(this.draftFunctionValues.get(key), 0);
                            }
                        });
                        if (nextItem !== item) {
                            shopChanged = true;
                        }
                        return nextItem;
                    });

                    if (shopChanged || nextFunctions.some((item, index) => item !== shop.functions[index])) {
                        nextShop = {
                            ...nextShop,
                            shopTarget: sumPlantFunctionCrews(nextFunctions),
                            functions: nextFunctions
                        };
                        shopChanged = true;
                    }
                }

                if (shopChanged) {
                    sectionChanged = true;
                }

                return nextShop;
            });

            if (!sectionChanged) {
                return section;
            }

            return {
                ...section,
                shops: nextShops
            };
        });

        this.responseData = {
            ...this.responseData,
            sections: nextSections
        };
        this.filteredSectionsCache = {
            sectionsRef: null,
            month: null,
            classification: null,
            driver: null,
            balanceStatus: null,
            value: []
        };
        this.visibleSectionsCache = {
            filteredSectionsRef: null,
            renderedSectionCount: null,
            expandedKeysSignature: null,
            value: []
        };
        this.sectionViewCache.clear();
        this.shopRowsCache.clear();
        this.clearDraftValues();
    }

    async runBusyTransition(label, work) {
        this.isActionBusy = true;
        this.actionBusyLabel = label;
        await this.waitForUiTick();
        try {
            await work();
            await this.waitForUiTick();
        } finally {
            this.isActionBusy = false;
            this.actionBusyLabel = '';
        }
    }

    afterNextPaint(callback) {
        const runner = typeof window !== 'undefined' && window.requestAnimationFrame
            ? window.requestAnimationFrame.bind(window)
            : (fn) => setTimeout(fn, 0);
        runner(() => {
            runner(() => {
                callback();
            });
        });
    }

    getVisibleExpandableShopKeys() {
        return this.visibleSections.flatMap((section) =>
            section.shops
                .filter((shop) => shop.functions.length)
                .map((shop) => buildShopKey(section.id, shop.id))
        );
    }

    updateSectionState(sectionId, updater) {
        const previousSections = this.responseData.sections;
        const cachedFilteredSections =
            this.filteredSectionsCache.sectionsRef === previousSections ? this.filteredSectionsCache.value : null;
        let didChange = false;
        let nextSection = null;
        const nextSections = this.responseData.sections.map((section) => {
            if (section.id !== sectionId) {
                return section;
            }
            didChange = true;
            nextSection = updater(section);
            return nextSection;
        });

        if (!didChange) {
            return;
        }

        if (cachedFilteredSections) {
            this.filteredSectionsCache = {
                ...this.filteredSectionsCache,
                sectionsRef: nextSections,
                value: cachedFilteredSections.map((section) =>
                    section.id === sectionId ? nextSection : section
                )
            };
        } else {
        this.filteredSectionsCache = {
            sectionsRef: null,
            month: null,
            classification: null,
            driver: null,
            balanceStatus: null,
            value: []
        };
        }

        this.visibleSectionsCache = {
            filteredSectionsRef: null,
            renderedSectionCount: null,
            expandedKeysSignature: null,
            value: []
        };
        this.sectionViewCache.delete(sectionId);
        [...this.shopRowsCache.keys()].forEach((key) => {
            if (key.startsWith(`${sectionId}::`)) {
                this.shopRowsCache.delete(key);
            }
        });
        this.responseData = {
            ...this.responseData,
            sections: nextSections
        };
    }

    updateShopState(sectionId, shopId, updater) {
        this.updateSectionState(sectionId, (section) => {
            const shopIndex = section.shops.findIndex((shop) => shop.id === shopId);
            if (shopIndex === -1) {
                return section;
            }
            const nextShops = [...section.shops];
            nextShops[shopIndex] = updater(section.shops[shopIndex]);
            return {
                ...section,
                shops: nextShops
            };
        });
    }

    updateFunctionState(sectionId, shopId, functionId, updater) {
        this.updateShopState(sectionId, shopId, (shop) => {
            const functionIndex = shop.functions.findIndex((item) => item.id === functionId);
            if (functionIndex === -1) {
                return shop;
            }
            const nextFunctions = [...shop.functions];
            nextFunctions[functionIndex] = updater(shop.functions[functionIndex]);
            return {
                ...shop,
                shopTarget: sumPlantFunctionCrews(nextFunctions),
                functions: nextFunctions
            };
        });
    }

    getVisibleExpandedShopKeys() {
        const visibleExpandableShopKeys = new Set(this.getVisibleExpandableShopKeys());
        return this.expandedShopKeys.filter((key) => visibleExpandableShopKeys.has(key));
    }

    findLastSavedSection(sectionId) {
        return this.lastSavedLookupMaps.sectionMap.get(sectionId) || null;
    }

    findLastSavedShop(sectionId, shopId) {
        return this.lastSavedLookupMaps.shopMap.get(buildShopKey(sectionId, shopId)) || null;
    }

    findLastSavedFunction(sectionId, shopId, functionId) {
        return this.lastSavedLookupMaps.functionMap.get(`${buildShopKey(sectionId, shopId)}::${functionId}`) || null;
    }

    findCurrentSection(sectionId) {
        return this.responseData.sections.find((section) => section.id === sectionId) || null;
    }

    findCurrentShop(sectionId, shopId) {
        const section = this.findCurrentSection(sectionId);
        return section?.shops.find((shop) => shop.id === shopId) || null;
    }

    findSessionBaselineSection(sectionId) {
        return this.sessionBaselineLookupMaps.sectionMap.get(sectionId) || null;
    }

    findSessionBaselineShop(sectionId, shopId) {
        return this.sessionBaselineLookupMaps.shopMap.get(buildShopKey(sectionId, shopId)) || null;
    }

    findSessionBaselineFunction(sectionId, shopId, functionId) {
        return this.sessionBaselineLookupMaps.functionMap.get(`${buildShopKey(sectionId, shopId)}::${functionId}`) || null;
    }

    getDirtySections() {
        return (this.responseData.sections || []).filter((section) => {
            const currentPayloadSection = buildPayloadAdjustment(section);
            const savedSection = this.findLastSavedSection(section.id);
            const savedPayloadSection = savedSection ? buildPayloadAdjustment(savedSection) : null;
            return JSON.stringify(currentPayloadSection) !== JSON.stringify(savedPayloadSection);
        });
    }

    getSectionExpandedSignature(section) {
        return section.shops
            .filter((shop) => this.expandedShopKeys.includes(buildShopKey(section.id, shop.id)))
            .map((shop) => shop.id)
            .join('|');
    }

    getRenderedSectionView(section) {
        const expandedSignature = this.getSectionExpandedSignature(section);
        const cachedView = this.sectionViewCache.get(section.id);

        if (
            cachedView?.sectionRef === section &&
            cachedView?.expandedSignature === expandedSignature &&
            cachedView?.lastSavedSectionsRef === this.lastSavedSections
        ) {
            return cachedView.value;
        }

        const totalChangesMade = this.calculateSectionTotal(section);
        const isBalanced = totalChangesMade === section.totalChangesNeeded;
        const value = {
            ...section,
            rows: this.buildRows(section),
            monthBandLabel: `${section.year} ${section.month}`.toUpperCase(),
            classificationBandClass: getClassificationBandClass(section.classification),
            totalChangesNeededDisplay: formatSignedNumber(section.totalChangesNeeded),
            totalChangesMadeDisplay: formatSignedNumber(totalChangesMade),
            balanceIconName: isBalanced ? 'utility:success' : 'utility:close',
            balanceIconClass: isBalanced ? 'balance-icon balance-icon_success' : 'balance-icon balance-icon_error',
            breakdownClass: isBalanced ? 'breakdown-value breakdown-value_success' : 'breakdown-value breakdown-value_error'
        };

        this.sectionViewCache.set(section.id, {
            sectionRef: section,
            expandedSignature,
            lastSavedSectionsRef: this.lastSavedSections,
            value
        });

        return value;
    }

    buildRows(section) {
        const rows = [];
        let rowNumber = 1;
        const expandedShopKeySet = new Set(this.expandedShopKeys);

        section.shops.forEach((shop) => {
            const shopKey = buildShopKey(section.id, shop.id);
            const isExpanded = expandedShopKeySet.has(shopKey);
            const lastSavedShop = this.findLastSavedShop(section.id, shop.id);
            const cachedShopRows = this.shopRowsCache.get(shopKey);
            if (
                cachedShopRows?.shopRef === shop &&
                cachedShopRows?.lastSavedShopRef === lastSavedShop &&
                cachedShopRows?.isExpanded === isExpanded &&
                cachedShopRows?.startLineNumber === rowNumber
            ) {
                rows.push(...cachedShopRows.rows);
                rowNumber += cachedShopRows.rowCount;
                return;
            }

            const shopRows = [];
            const startLineNumber = rowNumber;
            const shopTarget = shop.functions.length
                ? this.calculateShopTotal(section.id, shop)
                : this.getShopTargetValue(section.id, shop);
            const isShopTargetChanged = Number(lastSavedShop?.shopTarget || 0) !== Number(shopTarget || 0);
            shopRows.push({
                id: `${section.id}-${shop.id}`,
                rowClass: 'table-row table-row_shop',
                lineNumber: rowNumber++,
                isShop: true,
                isFunction: false,
                sectionId: section.id,
                shopId: shop.id,
                shopName: shop.shopName,
                shopTarget,
                shopTargetDisplay: formatSignedNumber(shopTarget),
                shopTargetCellClass: getChangedCellClass(isShopTargetChanged),
                shopTargetValueClass: isShopTargetChanged
                    ? 'shop-target-value shop-target-value_highlight'
                    : 'shop-target-value',
                shopTargetInputClass: isShopTargetChanged ? 'editable-number-input editable-number-input_changed' : 'editable-number-input',
                totalDisplay: formatSignedNumber(this.calculateShopTotal(section.id, shop)),
                toggleIconName: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                actionIconName: 'utility:chevrondown',
                hasFunctions: shop.functions.length > 0,
                isComputedShopTarget: shop.functions.length > 0
            });

            if (!isExpanded) {
                this.shopRowsCache.set(shopKey, {
                    shopRef: shop,
                    lastSavedShopRef: lastSavedShop,
                    isExpanded,
                    startLineNumber,
                    rowCount: shopRows.length,
                    rows: shopRows
                });
                rows.push(...shopRows);
                return;
            }

            shop.functions.forEach((item) => {
                const lastSavedFunction = this.findLastSavedFunction(section.id, shop.id, item.id);
                const crew1 = this.getFunctionFieldValue(section.id, shop.id, item, 'crew1');
                const crew2 = this.getFunctionFieldValue(section.id, shop.id, item, 'crew2');
                const crew3 = this.getFunctionFieldValue(section.id, shop.id, item, 'crew3');
                const isCrew1Changed = Number(lastSavedFunction?.crew1 || 0) !== Number(crew1 || 0);
                const isCrew2Changed = Number(lastSavedFunction?.crew2 || 0) !== Number(crew2 || 0);
                const isCrew3Changed = Number(lastSavedFunction?.crew3 || 0) !== Number(crew3 || 0);
                shopRows.push({
                    id: item.id,
                    rowClass: 'table-row table-row_function',
                    lineNumber: rowNumber++,
                    isShop: false,
                    isFunction: true,
                    sectionId: section.id,
                    shopId: shop.id,
                    functionId: item.id,
                    plantFunctionId: item.plantFunctionId,
                    masterName: item.masterName,
                    recordId: item.recordId,
                    recordDisplayName: item.recordDisplayName,
                    plantProgram: item.plantProgram,
                    gwbFunctionId: item.gwbFunctionId,
                    plantFunctionMasterId: item.plantFunctionMasterId,
                    plantProgramId: item.plantProgramId,
                    gwbFunctionUrl: item.gwbFunctionUrl,
                    plantFunctionUrl: item.plantFunctionUrl,
                    plantFunctionMasterUrl: item.plantFunctionMasterUrl,
                    plantProgramUrl: item.plantProgramUrl,
                    crew1,
                    crew2,
                    crew3,
                    crew1Display: formatSignedNumber(crew1),
                    crew2Display: formatSignedNumber(crew2),
                    crew3Display: formatSignedNumber(crew3),
                    crew1CellClass: getChangedCellClass(isCrew1Changed),
                    crew2CellClass: getChangedCellClass(isCrew2Changed),
                    crew3CellClass: getChangedCellClass(isCrew3Changed),
                    crew1InputClass: isCrew1Changed ? 'editable-number-input editable-number-input_changed' : 'editable-number-input',
                    crew2InputClass: isCrew2Changed ? 'editable-number-input editable-number-input_changed' : 'editable-number-input',
                    crew3InputClass: isCrew3Changed ? 'editable-number-input editable-number-input_changed' : 'editable-number-input',
                    totalDisplay: formatSignedNumber(this.calculateFunctionTotal(section.id, shop.id, item)),
                    actionIconName: 'utility:chevrondown'
                });
            });

            this.shopRowsCache.set(shopKey, {
                shopRef: shop,
                lastSavedShopRef: lastSavedShop,
                isExpanded,
                startLineNumber,
                rowCount: shopRows.length,
                rows: shopRows
            });
            rows.push(...shopRows);
        });

        return rows;
    }

    calculateSectionTotal(section) {
        return section.shops.reduce((sum, shop) => sum + this.calculateShopTotal(section.id, shop), 0);
    }

    isSectionBalanced(section) {
        return this.calculateSectionTotal(section) === Number(section.totalChangesNeeded || 0);
    }

    calculateShopTotal(sectionId, shop) {
        if (!shop.functions.length) {
            return this.getShopTargetValue(sectionId, shop);
        }
        return shop.functions.reduce((sum, item) => sum + this.calculateFunctionTotal(sectionId, shop.id, item), 0);
    }

    calculateFunctionTotal(sectionId, shopId, item) {
        return (
            this.getFunctionFieldValue(sectionId, shopId, item, 'crew1') +
            this.getFunctionFieldValue(sectionId, shopId, item, 'crew2') +
            this.getFunctionFieldValue(sectionId, shopId, item, 'crew3')
        );
    }

    clearCompletionValidationError() {
        this.completionValidationError = null;
    }
}