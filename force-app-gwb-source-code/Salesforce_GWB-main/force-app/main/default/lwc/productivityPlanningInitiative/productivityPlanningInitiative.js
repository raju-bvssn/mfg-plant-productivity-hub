import { LightningElement, track, api, wire } from 'lwc';
import getInitiativeRecords from '@salesforce/apex/ProdPlanInitiativeCntrl.getInitiativeRecords';
import hasGwbSystemAdminPermission from '@salesforce/customPermission/GWB_System_Admin';
import hasPlantAdminPermission from '@salesforce/customPermission/Plant_Admin';
import { NavigationMixin } from 'lightning/navigation';
import { IsConsoleNavigation, getFocusedTabInfo, openSubtab } from 'lightning/platformWorkspaceApi';

const POSITION_ADJUSTMENT_MISMATCH_TOOLTIP =
    'Value mismatch. Update the Forecast Total Adjustments Made value to match this value.';

export default class ProductivityPlanningInitiative extends NavigationMixin(LightningElement) {
    _appliedFilterWrapper = {};
    //_plant = 'a05WE00000e6a3uYAA';
    @api
    get appliedFilterWrapper() {
        return this._appliedFilterWrapper;
    }
    set appliedFilterWrapper(value) {
        this._appliedFilterWrapper = value || {};
        this.assignFiltersFromWrapper(this._appliedFilterWrapper);
    }
    /*@api
    get plant() {
        return this._plant;
    }
    set plant(value) {
        this._plant = value;
        if (this._plant) {
            this.loadInitiativeRecords();
        }
    }*/
    @api year = '';
    @api shop = '';
    @api month = '';
    @api classification = '';
    @api driver = '';
    @api baseSupp = '';
    @api initiativeType = '';
    @api initiativeStatus = '';
    @api excludeFromGWB = '';
    @api plant = '';
    @api plantName = '';
    @api plantRegion = '';
    @track groupedByMonth = [];
    showMismatchOnly = false;
    canShowAddButton = hasGwbSystemAdminPermission || hasPlantAdminPermission;
    isConsoleNavigation = false;
    showCreateInitiativeModal = false;
    isLoading = false;
    showCreateError = false;
    createErrorMessage = '';
    createErrorTimeout;
    currentYear = new Date().getFullYear();
    error;

    monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ];

    get requestPayload() {
        return {
            plant: this.plant,
            shop: this.shop,
            year: String(this.year),
            month: this.month,
            classification: this.classification,
            driver: this.driver,
            baseSupp: this.baseSupp,
            initiativeType: this.initiativeType,
            initiativeStatus: this.initiativeStatus,
            excludeFromGWB: this.excludeFromGWB
        };
    }

    get visibleGroupedByMonth() {
        if (!this.showMismatchOnly) {
            return this.groupedByMonth;
        }

        return this.groupedByMonth
            .map((monthGroup) => {
                const items = monthGroup.items.filter((record) => record.positionAdjustmentMismatch);
                return {
                    ...monthGroup,
                    items,
                    positionAdjustmentTotal: items.reduce((total, record) => {
                        const positionAdjustment = Number(record.Position_Adjustment__c);
                        return Number.isFinite(positionAdjustment)
                            ? total + positionAdjustment
                            : total;
                    }, 0)
                };
            })
            .filter((monthGroup) => monthGroup.items.length > 0);
    }

    /*connectedCallback() {
        if (this.plant) {
            this.loadInitiativeRecords();
        }
    }*/

    assignFiltersFromWrapper(wrapper) {
        this.year = wrapper.year ?? this.year;
        this.shop = wrapper.shop ?? this.shop;
        this.month = wrapper.month ?? this.month;
        this.classification = wrapper.classification ?? this.classification;
        this.driver = wrapper.driver ?? this.driver;
        this.baseSupp = wrapper.baseSupp ?? this.baseSupp;
        this.initiativeType = wrapper.initiativeType ?? this.initiativeType;
        this.initiativeStatus = wrapper.initiativeStatus ?? this.initiativeStatus;
        this.excludeFromGWB = wrapper.excludeFromGWB ?? this.excludeFromGWB;
        this.plantName = wrapper.plantName ?? this.plantName;
        this.plantRegion = wrapper.plantRegion ?? this.plantRegion;
        this.plant = wrapper.plant;
            this.loadInitiativeRecords();
        
    }

    async loadInitiativeRecords() {
        if (!this.plant) {
            this.groupedByMonth = [];
            return;
        }

        this.isLoading = true;
        try {
            const request = JSON.parse(JSON.stringify(this.requestPayload));
            console.log('this is request',request);
            const data = await getInitiativeRecords({ request });
            console.log('this is data',data);
            // Force reactivity by creating fresh array/object references.
            const records = Array.isArray(data.records)
                ? JSON.parse(JSON.stringify(data.records))
                : [];
            
            const initiativeRecords = records.map((record) => ({ ...record }));
            console.log('this is initiativeRecords',initiativeRecords);
            this.formatData(initiativeRecords);
            this.error = undefined;
        } catch (error) {
            this.error = error;
            console.log('this is error',error);
            this.groupedByMonth = [];
        } finally {
            this.isLoading = false;
        }
    }

    formatData(records) {
        const parsedYear = Number.parseInt(this.year, 10);
        const selectedYear = Number.isFinite(parsedYear) ? parsedYear : this.currentYear;
        let monthBuckets = this.monthNames.map(name => ({
            monthName: name,
            items: [],
            sectionLabel: '',
            positionAdjustmentTotal: 0,
            isOpen: true,
            chevronIcon: 'utility:chevrondown'
        }));

        records.forEach(rec => {
            if (!rec.Effective_Date__c) {
                return;
            }

            const startDate = this.parseDateParts(rec.Effective_Date__c);
            if (!startDate) {
                return;
            }
            const startYear = startDate.year;
            const startMonth = startDate.month;

            let targetPlacements = [];
            if (startYear === selectedYear) {
                targetPlacements.push({ monthIndex: startMonth, placementType: 'effective' });
            }

            if (targetPlacements.length) {
                const recUrl = `/lightning/r/Initiative__c/${rec.Id}/view`;
                const basePositionAdjustment = Number(rec.Position_Adjustment__c);
                const forecastTotalAdjustment = Number(rec.Total_Calculated_Adjustment__c || 0);

                targetPlacements.forEach(({ monthIndex, placementType }) => {
                    const adjustedPositionValue = Number.isFinite(basePositionAdjustment)
                        ? basePositionAdjustment
                        : rec.Position_Adjustment__c;
                    const positionAdjustmentMismatch = Number(adjustedPositionValue || 0) !== forecastTotalAdjustment;
                    console.log(positionAdjustmentMismatch, adjustedPositionValue, forecastTotalAdjustment);
                    
                    monthBuckets[monthIndex].items.push({
                        ...rec,
                        initiativeTypeDisplay: rec.Initiative_Type__c,
                        effectiveDateDisplay: this.formatDateForDisplay(rec.Effective_Date__c),
                        endDateDisplay: this.formatDateForDisplay(rec.End_Date__c),
                        Position_Adjustment__c: adjustedPositionValue,
                        positionAdjustmentMismatch,
                        positionAdjustmentCellClass: positionAdjustmentMismatch
                            ? 'position-adjustment-value-cell position-adjustment-value-cell_mismatch'
                            : 'position-adjustment-value-cell',
                        positionAdjustmentMismatchTooltip: POSITION_ADJUSTMENT_MISMATCH_TOOLTIP,
                        recordUrl: recUrl,
                        uniqueKey: `${rec.Id}-${monthIndex}-${placementType}`
                    });
                    monthBuckets[monthIndex].positionAdjustmentTotal += Number.isFinite(adjustedPositionValue)
                        ? adjustedPositionValue
                        : 0;
                });
            }
        });

        monthBuckets.forEach(bucket => {
            bucket.sectionLabel = bucket.monthName;
        });

        const normalizedSelectedMonth = (this.month || '').trim().toLowerCase();
        if (normalizedSelectedMonth && normalizedSelectedMonth !== 'all') {
            let selectedMonthName = '';
            const numericMonth = Number.parseInt(normalizedSelectedMonth, 10);

            if (Number.isFinite(numericMonth) && numericMonth >= 1 && numericMonth <= 12) {
                selectedMonthName = this.monthNames[numericMonth - 1];
            } else {
                const matchedMonth = this.monthNames.find(
                    (monthName) => monthName.toLowerCase() === normalizedSelectedMonth
                );
                selectedMonthName = matchedMonth || '';
            }

            this.groupedByMonth = selectedMonthName
                ? monthBuckets.filter((bucket) => bucket.monthName === selectedMonthName)
                : monthBuckets;
            return;
        }

        this.groupedByMonth = monthBuckets;
    }

    parseDateParts(dateValue) {
        if (!dateValue) {
            return null;
        }

        const parts = dateValue.split('-');
        if (parts.length < 2) {
            return null;
        }

        const year = parseInt(parts[0], 10);
        const month = parseInt(parts[1], 10) - 1;
        if (Number.isNaN(year) || Number.isNaN(month) || month < 0 || month > 11) {
            return null;
        }

        return { year, month };
    }

    formatDateForDisplay(dateValue) {
        if (!dateValue || typeof dateValue !== 'string') {
            return '';
        }

        const parts = dateValue.split('-');
        if (parts.length < 3) {
            return dateValue;
        }

        const year = parts[0];
        const month = parts[1];
        const day = parts[2];
        return `${month}/${day}/${year}`;
    }

    get cardTitle() {
        const titleParts = [
            this.year || this.currentYear,
            this.plantName,
            this.shop
        ].filter((value) => value);

        return titleParts.join(' ');
    }

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(value) {
        this.isConsoleNavigation = value?.data === true;
    }

    async handleRecordLinkClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget?.dataset?.recordId;
        if (!recordId) {
            return;
        }

        if (this.isConsoleNavigation) {
            try {
                const focusedTab = await getFocusedTabInfo();
                await openSubtab(focusedTab.tabId, {
                    recordId,
                    focus: true
                });
                return;
            } catch (error) {
                // eslint-disable-next-line no-console
                console.log('Unable to open record as subtab', error);
            }
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Initiative__c',
                actionName: 'view'
            }
        });
    }

    handleCreateInitiative() {
        const isPlantEmpty = !this.plant;
        const isShopEmpty = !this.shop;

        if (isPlantEmpty || isShopEmpty) {
            this.showTransientCreateError('Plant or Shop are empty. Please select those to create Initiative Records');
            return;
        }

        this.showCreateInitiativeModal = true;
    }

    showTransientCreateError(message) {
        this.createErrorMessage = message;
        this.showCreateError = true;

        if (this.createErrorTimeout) {
            clearTimeout(this.createErrorTimeout);
        }

        this.createErrorTimeout = setTimeout(() => {
            this.showCreateError = false;
            this.createErrorMessage = '';
            this.createErrorTimeout = null;
        }, 6000);
    }

    disconnectedCallback() {
        if (this.createErrorTimeout) {
            clearTimeout(this.createErrorTimeout);
            this.createErrorTimeout = null;
        }
    }

    handleToggleMonth(event) {
        const monthName = event.currentTarget.dataset.month;
        if (!monthName) {
            return;
        }

        this.groupedByMonth = this.groupedByMonth.map((group) => {
            if (group.monthName !== monthName) {
                return group;
            }

            const isOpen = !group.isOpen;
            return {
                ...group,
                isOpen,
                chevronIcon: isOpen ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    handleRefresh() {
        this.loadInitiativeRecords();
    }

    handleMismatchValuesToggle(event) {
        this.showMismatchOnly = event.detail.checked;
    }

    handleCloseCreateInitiativeModal() {
        this.showCreateInitiativeModal = false;
    }

    get flowInputVariables() {
        return [
            {
                name: 'Plant_Id',
                type: 'String',
                value: this.plant || ''
            },
            {
                name: 'Plant_Name',
                type: 'String',
                value: this.plantName || ''
            },
            {
                name: 'Shop',
                type: 'String',
                value: this.shop || ''
            },
            {
                name: 'Plant_Region',
                type: 'String',
                value: this.plantRegion || ''
            }
        ];
    }

    handleFlowStatusChange(event) {
        if (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN') {
            this.showCreateInitiativeModal = false;
            this.handleRefresh();
        }
    }
}