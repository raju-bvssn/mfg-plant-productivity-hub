import { LightningElement, track, wire } from "lwc";
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabIcon,
    setTabLabel
} from "lightning/platformWorkspaceApi";

const FILTER_CHANGE_SOURCE_INITIAL_DEFAULTS = "initial-defaults";
const FILTER_CHANGE_SOURCE_SUMMARY_TAB_ENFORCED = "summary-tab-enforced";

export default class ProductivityPlanningSuite extends LightningElement {
    @track appliedFilters = {};
    @track activeTabValue = "summary";

    headerIconName = "standard:workspace";
    headerIconAltText = "Workspace";
    tabLabel = "Productivity Planning Suite";
    _hasSyncedTabPresentation = false;
    _isSyncInProgress = false;
    _tabSyncAttempts = 0;
    _maxTabSyncAttempts = 10;
    _tabSyncRetryDelayMs = 300;
    _isConsoleNavigation = false;

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(value) {
        this._isConsoleNavigation = value?.data ?? value ?? false;
        if (this._isConsoleNavigation) {
            this.syncConsoleTabPresentation();
        }
    }

    connectedCallback() {
        this.syncConsoleTabPresentation();
    }

    renderedCallback() {
        this.syncConsoleTabPresentation();
    }

    async syncConsoleTabPresentation() {
        if (this._hasSyncedTabPresentation || this._isSyncInProgress || !this._isConsoleNavigation) {
            return;
        }

        this._isSyncInProgress = true;
        try {
            const { tabId } = await getFocusedTabInfo();
            await Promise.all([
                setTabLabel(tabId, this.tabLabel),
                setTabIcon(tabId, this.headerIconName, { iconAlt: this.headerIconAltText })
            ]);
            this._hasSyncedTabPresentation = true;
        } catch (error) {
            if (this._tabSyncAttempts < this._maxTabSyncAttempts) {
                this._tabSyncAttempts += 1;
                window.setTimeout(() => this.syncConsoleTabPresentation(), this._tabSyncRetryDelayMs);
            }
        } finally {
            this._isSyncInProgress = false;
        }
    }

    normalizeFilters(filters) {
        return {
            ...(filters || {}),
            plantRegion: filters?.plantRegion || ""
        };
    }

    handleFilterChange(event) {
        const source = event?.detail?.source;
        const filters = event?.detail?.filters;
        const isAllowedSource =
            source === FILTER_CHANGE_SOURCE_INITIAL_DEFAULTS || source === FILTER_CHANGE_SOURCE_SUMMARY_TAB_ENFORCED;

        if (isAllowedSource && filters) {
            this.appliedFilters = this.normalizeFilters(filters);
        }
    }

    handleApply(event) {
        this.appliedFilters = this.normalizeFilters(event.detail);
    }

    handleTabActive(event) {
        this.activeTabValue = event.target.value;
    }
}