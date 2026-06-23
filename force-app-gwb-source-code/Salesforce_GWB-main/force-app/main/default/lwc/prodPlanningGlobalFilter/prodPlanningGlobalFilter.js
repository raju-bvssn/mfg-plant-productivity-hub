import { api, LightningElement, track } from "lwc";
import getGlobalFilters from "@salesforce/apex/ProdPlanningGlobalFilterCntrl.getGlobalFilters";
import hasCentralAdminPermission from "@salesforce/customPermission/Central_Admin";
import hasRegionalAdminPermission from "@salesforce/customPermission/Regional_Admin";

const EXCLUDE_FROM_GWB_NO = "No";
const SUMMARY_TAB_VALUE = "summary";
const ALL_OPTION_VALUE = "All";
const OTS_OPTION_VALUE = "OTS";
const SUMMARY_LOCKED_FIELDS = ["month", "initiativeType", "initiativeStatus"];
const FILTER_CHANGE_SOURCE_INITIAL_DEFAULTS = "initial-defaults";
const FILTER_CHANGE_SOURCE_SUMMARY_TAB_ENFORCED = "summary-tab-enforced";

const EMPTY_FILTERS = {
    plant: "",
    shop: "",
    year: "",
    month: "",
    classification: "",
    driver: "",
    baseSupp: "",
    initiativeType: "",
    initiativeStatus: "",
    excludeFromGWB: ""
};

export default class ProdPlanningGlobalFilter extends LightningElement {
    @track options = {
        plant: [],
        shop: [],
        year: [],
        month: [],
        classification: [],
        driver: [],
        baseSupp: [],
        initiativeType: [],
        initiativeStatus: [],
        excludeFromGWB: []
    };

    @track filters = { ...EMPTY_FILTERS };
    @track isLoading = true;
    @track errorMessage = "";
    @track isCollapsed = false;

    defaultFilters = { ...EMPTY_FILTERS };
    shopsByPlant = {};
    hasLoadedFilters = false;

    @api initialFilters = {};
    _activeTab = SUMMARY_TAB_VALUE;

    @api
    get activeTab() {
        return this._activeTab;
    }

    set activeTab(value) {
        const wasSummaryTabActive = this._activeTab === SUMMARY_TAB_VALUE;
        this._activeTab = value;
        const isSwitchingToSummary = !wasSummaryTabActive && this.isSummaryTabActive;

        if (this.hasLoadedFilters && isSwitchingToSummary) {
            // Always notify Summary when entering the tab so it can refresh rows
            // with the latest filter state (including any enforced summary filters).
            this.enforceSummaryTabFilters();
            this.notifyChange(FILTER_CHANGE_SOURCE_SUMMARY_TAB_ENFORCED);
        }
    }

    get isExcludeFromGwbLocked() {
        return hasCentralAdminPermission || hasRegionalAdminPermission;
    }

    get isSummaryTabActive() {
        return this.activeTab === SUMMARY_TAB_VALUE;
    }

    get isShopDisabled() {
        return (this.options.shop || []).length === 0;
    }

    get collapseIconName() {
        return this.isCollapsed ? "utility:chevronright" : "utility:chevrondown";
    }

    get collapseAltText() {
        return this.isCollapsed ? "Expand filters" : "Collapse filters";
    }

    connectedCallback() {
        this.loadFilters();
    }

    async loadFilters() {
        this.isLoading = true;
        this.errorMessage = "";

        try {
            const response = await getGlobalFilters({ requestPayload: this.initialFilters || {} });
            this.shopsByPlant = response?.shopsByPlant || {};

            this.options = {
                plant: response?.plant || [],
                shop: [],
                year: this.toOptions(response?.year),
                month: this.toOptions(response?.month),
                classification: this.toOptions(response?.classification),
                driver: this.toOptions(response?.driver),
                baseSupp: this.toOptions(response?.baseSupp),
                initiativeType: this.toOptions(response?.initiativeType),
                initiativeStatus: this.toOptions(response?.initiativeStatus),
                excludeFromGWB: this.toOptions(response?.excludeFromGWB).filter(
                    (option) => option.value !== ALL_OPTION_VALUE
                )
            };

            this.defaultFilters = this.buildDefaultFilters();
            this.filters = this.applyRoleBasedFilterBehavior({ ...this.defaultFilters, ...this.initialFilters });
            this.syncShopsAndSelection();
            this.enforceSummaryTabFilters();
            this.hasLoadedFilters = true;
            this.notifyChange(FILTER_CHANGE_SOURCE_INITIAL_DEFAULTS);
        } catch (error) {
            this.errorMessage = error?.body?.message || "Unable to load global filters.";
        } finally {
            this.isLoading = false;
        }
    }

    buildDefaultFilters() {
        const currentYear = String(new Date().getFullYear());
        return {
            plant: this.options.plant[0]?.value || "",
            shop: "",
            year: this.getDefaultOptionValue(this.options.year, currentYear),
            month: this.options.month[0]?.value || "",
            classification: this.getDefaultOptionValue(this.options.classification, ALL_OPTION_VALUE),
            driver: this.getDefaultOptionValue(this.options.driver, OTS_OPTION_VALUE),
            baseSupp: this.getDefaultOptionValue(this.options.baseSupp, ALL_OPTION_VALUE),
            initiativeType: this.options.initiativeType[0]?.value || "",
            initiativeStatus: this.options.initiativeStatus[0]?.value || "",
            excludeFromGWB: this.getExcludeFromGwbDefaultValue()
        };
    }

    getDefaultOptionValue(options, preferredValue) {
        const safeOptions = options || [];
        const preferredOption = safeOptions.find((option) => option.value === preferredValue);
        if (preferredOption) {
            return preferredOption.value;
        }
        return safeOptions[0]?.value || "";
    }

    getExcludeFromGwbDefaultValue() {
        const hasNoOption = this.options.excludeFromGWB.some((option) => option.value === EXCLUDE_FROM_GWB_NO);
        if (hasNoOption) {
            return EXCLUDE_FROM_GWB_NO;
        }
        return this.options.excludeFromGWB[0]?.value || "";
    }

    applyRoleBasedFilterBehavior(currentFilters) {
        if (!this.isExcludeFromGwbLocked) {
            return currentFilters;
        }

        return {
            ...currentFilters,
            excludeFromGWB: EXCLUDE_FROM_GWB_NO
        };
    }

    enforceSummaryTabFilters() {
        if (!this.isSummaryTabActive) {
            return false;
        }

        let hasChanges = false;
        const nextFilters = { ...this.filters };
        for (const field of SUMMARY_LOCKED_FIELDS) {
            if (!this.hasOptionValue(field, ALL_OPTION_VALUE)) {
                continue;
            }
            if (nextFilters[field] !== ALL_OPTION_VALUE) {
                nextFilters[field] = ALL_OPTION_VALUE;
                hasChanges = true;
            }
        }

        if (hasChanges) {
            this.filters = this.applyRoleBasedFilterBehavior(nextFilters);
        }
        return hasChanges;
    }

    hasOptionValue(fieldName, targetValue) {
        return (this.options[fieldName] || []).some((option) => option.value === targetValue);
    }

    toOptions(values) {
        if (!values || !Array.isArray(values)) {
            return [];
        }
        return values.map((value) => ({ label: value, value }));
    }

    get selectedPlantLabel() {
        const selectedPlant = this.options.plant.find((option) => option.value === this.filters.plant);
        return selectedPlant?.label || "";
    }

    get selectedPlantRegion() {
        const selectedPlant = this.options.plant.find((option) => option.value === this.filters.plant);
        return selectedPlant?.plantRegion || "";
    }

    syncShopsAndSelection() {
        const shops = this.shopsByPlant[this.selectedPlantLabel] || [];
        this.options = {
            ...this.options,
            shop: this.toOptions(shops)
        };

        if (!shops.includes(this.filters.shop)) {
            this.filters = {
                ...this.filters,
                shop: shops[0] || ""
            };
        }
    }

    handleSelectChange(event) {
        const field = event.target.name;
        const value = event.detail.value;
        this.filters = this.applyRoleBasedFilterBehavior({ ...this.filters, [field]: value });

        if (field === "plant") {
            this.syncShopsAndSelection();
        }
    }

    get filtersWithPlantName() {
        return {
            ...this.filters,
            plantName: this.selectedPlantLabel,
            plantRegion: this.selectedPlantRegion
        };
    }

    handleApply() {
        this.dispatchEvent(new CustomEvent("apply", { detail: { ...this.filtersWithPlantName } }));
    }

    handleReset() {
        this.filters = this.applyRoleBasedFilterBehavior({ ...this.defaultFilters });
        this.enforceSummaryTabFilters();
        this.syncShopsAndSelection();
        this.dispatchEvent(new CustomEvent("reset", { detail: { ...this.filtersWithPlantName } }));
    }

    handleCancel() {
        this.filters = this.applyRoleBasedFilterBehavior({ ...this.defaultFilters });
        this.enforceSummaryTabFilters();
        this.syncShopsAndSelection();
        this.dispatchEvent(new CustomEvent("cancel", { detail: { ...this.filtersWithPlantName } }));
    }

    handleToggleCollapse() {
        this.isCollapsed = !this.isCollapsed;
    }

    notifyChange(source) {
        this.dispatchEvent(
            new CustomEvent("filterschange", {
                detail: {
                    source,
                    filters: { ...this.filtersWithPlantName }
                }
            })
        );
    }
}