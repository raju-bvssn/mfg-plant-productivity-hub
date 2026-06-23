/**
 * @description       : Manage Plant Shops Quick Action Component V2
 * @group             : 
 * @last modified on  : 01-15-2025
 * @last modified by  : 
**/
import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from "lightning/refresh";
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import CUSTOM_MODAL_CSS from '@salesforce/resourceUrl/QuickActionWidthFixCss'; // Replace CustomModalWidthCSS with your static resource name

// Field reference for Plant Name
const PLANT_NAME_FIELD = 'Plant__c.Name';

// Accordion shop values - use normalized comparison (trim) to handle API/whitespace variations
const SHOP_ALL = 'All';
const SHOP_ALL_EXCEPT_BODY_PAINT = 'All Except Body, Paint';
const SHOP_ALL_EXCEPT_BODY_PAINT_ALT = 'All Except Body Paint'; // alternate without comma
const isShopAll = (s) => (s || '').trim() === SHOP_ALL;
const isShopAllExceptBodyPaint = (s) => {
    const t = (s || '').trim();
    return t === SHOP_ALL_EXCEPT_BODY_PAINT || t === SHOP_ALL_EXCEPT_BODY_PAINT_ALT;
};



import getInitialData from '@salesforce/apex/ManagePlantShopsController.getInitialData';
import savePrograms from '@salesforce/apex/ManagePlantShopsController.savePrograms';
import updateSinglePlantProgram from '@salesforce/apex/ManagePlantShopsController.updateSinglePlantProgram';
import updatePlantProgramOpPlan from '@salesforce/apex/ManagePlantShopsController.updatePlantProgramOpPlan';
import savePlantShops from '@salesforce/apex/ManagePlantShopsController.savePlantShops';
import createPlantFunctions from '@salesforce/apex/ManagePlantShopsController.createPlantFunctions';
import getOperationPlanShifts from '@salesforce/apex/ManagePlantShopsController.getOperationPlanShifts';
import getShopMastersByCriteria from '@salesforce/apex/ManagePlantShopsController.getShopMastersByCriteria';
import propagateOperationPlanToMatchingPrograms from '@salesforce/apex/ManagePlantShopsController.propagateOperationPlanToMatchingPrograms';
import propagateProgramCodeAndNameToMatchingPrograms from '@salesforce/apex/ManagePlantShopsController.propagateProgramCodeAndNameToMatchingPrograms';
import setIncludeFalseForMatchingPrograms from '@salesforce/apex/ManagePlantShopsController.setIncludeFalseForMatchingPrograms';
import setIncludeTrueForMatchingPrograms from '@salesforce/apex/ManagePlantShopsController.setIncludeTrueForMatchingPrograms';
import updatePlantProgramsIncludeAndAuth from '@salesforce/apex/ManagePlantShopsController.updatePlantProgramsIncludeAndAuth';
import reparentEquationFunctionsForDeactivatedPrograms from '@salesforce/apex/ManagePlantShopsController.reparentEquationFunctionsForDeactivatedPrograms';
import getChildPlantPrograms from '@salesforce/apex/ManagePlantShopsController.getChildPlantPrograms';
import getOperationPlansForDropdown from '@salesforce/apex/ManagePlantShopsController.getOperationPlansForDropdown';
import ensurePlantProgramCodeExists from '@salesforce/apex/ManagePlantShopsController.ensurePlantProgramCodeExists';

export default class ManagePlantShopsV2 extends NavigationMixin(LightningElement) {
    @api recordId; // Plant ID from quick action context

    isLoading = false;
    @track isSaving = false;
    @track error;
    plantName;
    plantAuthSector = '';

    plantShops = [];
    shopMasters = [];
    shopPrograms = [];
    programMasters = []; // Program_Master__c records for the plant
    originalPlantProgramIds = new Set(); // Set of original Plant Program IDs (not cloned)
    
    // Cache for program code options by sector-productType combination
    programCodeOptionsCache = {}; // Key: "sector|productType", Value: array of options
    
    // Track original state for cancel functionality
    @track originalPlantShopRows = [];
    @track hasExistingPlantPrograms = false; // True if there are existing plant programs for this plant
    @track hasUnsavedChanges = false; // Track if any changes have been made
    
    // Accordion/expandable row properties
    @track expandedRows = new Set(); // Track which rows are expanded (by key)
    @track childProgramsMap = {}; // Map of row key -> child programs array

    // Deactivation / reparent modal properties
    @track showDeactivateProgramModal = false;
    @track deactivateProgramModalState = null;
    @track pendingEquationReparentRequests = [];

    // Shift change modal properties
    @track showShiftChangeModal = false;
    @track oldShiftCount = 0;
    @track newShiftCount = 0;
    @track auth3rdShiftValue = 0;
    @track pendingShiftChange = null; // Stores the context for the pending shift change
    @track workbookData = []; // List of Workbook records matching Plant Program criteria
    @track isLoadingFunctions = false;
    @track functionNameFilter = ''; // Filter for function name in the modal (deprecated, using columnFilters)
    
    // Allocate modal properties (new UI similar to workbookMonthlyData)
    @track showAllocateModal = false;
    @track allocateWorkbookData = []; // Workbook data for allocate modal
    @track allocateFilteredData = []; // Filtered workbook data for allocate modal
    @track allocateColumns = []; // Columns for allocate modal datatable
    @track isLoadingAllocateData = false;
    @track allocatePendingShiftChange = null; // Stores shift change context for allocate modal
    @track allocateDraftValues = []; // Draft values for allocate modal
    @track allocateDataMap = {}; // Data map for allocate modal
    @track allocateDatatableKey = '0'; // Force datatable re-render
    
    // Filters for allocate modal (same as workbookMonthlyData)
    @track allocateFilterFunction = '';
    @track allocateFilterFunctionalArea = '';
    @track allocateFilterClassification = '';
    @track allocateFilterYear = '';
    @track allocateFilterMonth = ''; // Start month filter
    
    // Excel-style column filters
    @track columnFilters = {
        function: [],
        programCode: [],
        functionalArea: [],
        shop: []
    };
    @track showFilterDropdowns = {
        function: false,
        programCode: false,
        functionalArea: false,
        shop: false
    };

    @track
    plantShopRows = [];

    // shopRules = new Map();
    programValues = ['A', 'B', 'C', 'D', 'E'];
    headerColumns = [
        { label: 'Sector', fieldName: 'authSector', type: 'text' },
        { label: 'Product Type', fieldName: 'productType', type: 'text' },
        { label: 'Shop', fieldName: 'shop', type: 'text' },
        ...this.programValues.map(pv => ({
            label: pv,
            fieldName: pv,
            type: 'checkbox',
            editable: 'true'
        }))
    ];

    // Program Code dropdown options for different scenarios
    assemblyProgramOptions = [
        { label: 'BET', value: 'BET' },
        { label: 'BET/BEV', value: 'BET/BEV' },
        { label: 'BEV', value: 'BEV' },
        { label: 'Car', value: 'Car' },
        { label: 'Enclosures', value: 'Enclosures' },
        { label: 'Full Size Truck/SUV', value: 'Full Size Truck/SUV' },
        { label: 'Mid Size SUV', value: 'Mid Size SUV' },
        { label: 'Mid Size Truck', value: 'Mid Size Truck' },
        { label: 'Mid Size Truck / Van', value: 'Mid Size Truck / Van' },
        { label: 'Van', value: 'Van' }
    ];

    gpsEngineProgramOptions = [
        { label: '8sp', value: '8sp' },
        { label: 'CSS', value: 'CSS' },
        { label: 'DMAX Diesel', value: 'DMAX Diesel' },
        { label: 'Gen V', value: 'Gen V' },
        { label: 'Gen V Comp Assist', value: 'Gen V Comp Assist' },
        { label: 'Gen 6', value: 'Gen 6' },
        { label: 'HFV6', value: 'HFV6' },
        { label: 'LT6', value: 'LT6' },
        { label: 'SGE', value: 'SGE' }
    ];

    gpsBatteryProgramOptions = [
        { label: 'BET', value: 'BET' },
        { label: 'BEV+', value: 'BEV+' },
        { label: 'eLCV', value: 'eLCV' },
        { label: 'Gen2', value: 'Gen2' },
        { label: 'PowerCube', value: 'PowerCube' },
        { label: 'TBO Module', value: 'TBO Module' },
        { label: 'TBO Pack', value: 'TBO Pack' },
        { label: 'Ultium', value: 'Ultium' }
    ];

    // Use imperative call inside connectedCallback, with dataLoad flag to ensure single load
    dataLoaded = false;
    
    // Operation Plan dropdown options
    @track operationPlanOptions = [];

    // Wire to get Plant Name
    @wire(getRecord, { recordId: '$recordId', fields: [PLANT_NAME_FIELD] })
    wiredPlant({ error, data }) {
        if (data) {
            const newPlantName = getFieldValue(data, PLANT_NAME_FIELD);
            const plantNameChanged = this.plantName !== newPlantName;
            this.plantName = newPlantName;
            console.log('🌳 Plant Name loaded:', this.plantName);
            
            // If plant name changed and we already have data, reload program codes
            if (plantNameChanged && this.plantShopRows && this.plantShopRows.length > 0) {
                console.log('🔄 Reloading program codes after plant name change');
                this.reloadProgramCodesAfterPlantNameLoad();
            }
        } else if (error) {
            console.error('Error loading plant name:', error);
        }
    }
    
    reloadProgramCodesAfterPlantNameLoad() {
        // Re-populate program codes based on plant name
        if (!this.plantShopRows || this.plantShopRows.length === 0) return;
        
        this.plantShopRows = this.plantShopRows.map(row => ({
            ...row,
            programLoop: row.programLoop.map(prog => {
                // Only update if no existing plantProgramId (don't override existing data from database)
                if (!prog.plantProgramId) {
                    const { programCode, programName, showDropdown } = this.getProgramInfo(
                        row.authSector,
                        row.productType,
                        row.shop,
                        prog.programValue
                    );
                    return {
                        ...prog,
                        programCode: programCode || prog.programCode || '',
                        programName: programName || prog.programName || '',
                        showDropdown: showDropdown !== undefined ? showDropdown : prog.showDropdown
                    };
                }
                return prog;
            })
        }));
        
        console.log('✅ Program codes reloaded after plant name load');
    }

    connectedCallback() {
        Promise.all([
            loadStyle(this, CUSTOM_MODAL_CSS)
        ]).then(() => {
            console.log('Styles loaded successfully');
        }).catch(error => {
            console.error('Error loading styles:', error);
        });
        
        // Load Operation Plan options for dropdown
        this.loadOperationPlanOptions();
    }
    
    async loadOperationPlanOptions() {
        try {
            const operationPlans = await getOperationPlansForDropdown();
            this.operationPlanOptions = operationPlans.map(op => ({
                label: op.name,
                value: op.id
            }));
            console.log('Operation Plan options loaded:', this.operationPlanOptions.length);
        } catch (error) {
            console.error('Error loading Operation Plan options:', error);
            this.showToast('Error', 'Failed to load Operation Plan options', 'error');
        }
    }
    
    renderedCallback() {
        // Sync checkbox states with filters when modal is open
        if (this.showShiftChangeModal) {
            // Use setTimeout to ensure DOM is fully rendered
            setTimeout(() => {
                this.syncFilterCheckboxStates();
            }, 0);
        }
    }
    
    syncFilterCheckboxStates() {
        // Sync Function filter checkboxes
        const functionCheckboxes = this.template.querySelectorAll('[data-filter-column="function"]');
        functionCheckboxes.forEach(checkbox => {
            const value = checkbox.value;
            if (value) {
                checkbox.checked = this.columnFilters.function.includes(value);
            }
        });
        
        // Sync Program Code filter checkboxes
        const programCodeCheckboxes = this.template.querySelectorAll('[data-filter-column="programCode"]');
        programCodeCheckboxes.forEach(checkbox => {
            const value = checkbox.value;
            if (value) {
                checkbox.checked = this.columnFilters.programCode.includes(value);
            }
        });
        
        // Sync Functional Area filter checkboxes
        const functionalAreaCheckboxes = this.template.querySelectorAll('[data-filter-column="functionalArea"]');
        functionalAreaCheckboxes.forEach(checkbox => {
            const value = checkbox.value;
            if (value) {
                checkbox.checked = this.columnFilters.functionalArea.includes(value);
            }
        });
        
        // Sync Shop filter checkboxes
        const shopCheckboxes = this.template.querySelectorAll('[data-filter-column="shop"]');
        shopCheckboxes.forEach(checkbox => {
            const value = checkbox.value;
            if (value) {
                checkbox.checked = this.columnFilters.shop.includes(value);
            }
        });
    }
    
    // Close dropdowns when clicking outside
    handleClickOutside(event) {
        if (this.showShiftChangeModal) {
            const isFilterDropdown = event.target.closest('.excel-filter-dropdown');
            const isFilterButton = event.target.closest('.excel-filter-button');
            
            if (!isFilterDropdown && !isFilterButton) {
                // Close all dropdowns
                this.showFilterDropdowns = {
                    function: false,
                    programCode: false,
                    functionalArea: false,
                    shop: false
                };
            }
        }
    }
    
    // ========== ALLOCATE MODAL HANDLERS ==========
    
    // Handle Allocate button click - Show allocateShiftPositions component below
    async handleAllocateClick(event) {
        try {
            const { shopMasterId, programValue } = event.currentTarget.dataset;
            
            // Find the program to get shift change info
            const row = this.plantShopRows.find(r => r.key === shopMasterId);
            if (!row) return;
            
            const program = row.programLoop.find(p => p.programValue === programValue);
            if (!program || !program.operationPlanId) {
                this.showToast('Error', 'Please select an Operation Plan first', 'error');
                return;
            }
            
            // Get plant program ID - required for allocate page
            let plantProgramId = program.plantProgramId;
            
            // If plantProgramId doesn't exist, auto-save the program first
            if (!plantProgramId) {
                this.showToast('Info', 'Saving program before opening Allocate page...', 'info');
                try {
                    // Save the program first to get the plantProgramId (without closing the quick action)
                    const saveResult = await this.handleSaveForAllocate(shopMasterId, programValue);
                    if (!saveResult || !saveResult.success) {
                        this.showToast('Error', saveResult?.errorMessage || 'Failed to save program. Please save manually and try again.', 'error');
                        return;
                    }
                    
                    // After save, get the plantProgramId from the save result
                    if (saveResult.plantProgramId) {
                        plantProgramId = saveResult.plantProgramId;
                    } else {
                        this.showToast('Error', 'Failed to retrieve saved program ID. Please save manually and try again.', 'error');
                        return;
                    }
                } catch (error) {
                    console.error('Error auto-saving before Allocate:', error);
                    const errorMessage = error?.body?.message || error?.message || 'Failed to save program. Please save manually and try again.';
                    this.showToast('Error', errorMessage, 'error');
                    return;
                }
            }
            
            let oldShifts, newShifts, newOperationPlanId;
            
            // If shift change info exists, use it
            if (program.shiftChangeInfo) {
                ({ oldShifts, newShifts, newOperationPlanId } = program.shiftChangeInfo);
                newOperationPlanId = newOperationPlanId || program.operationPlanId;
            } else {
                // No shift change info - fetch current shift count from operation plan
                try {
                    const currentOperationPlanId = program.operationPlanId;
                    const shiftData = await getOperationPlanShifts({ 
                        oldOpPlanId: currentOperationPlanId, 
                        newOpPlanId: currentOperationPlanId 
                    });
                    
                    if (shiftData && shiftData.newShifts) {
                        // Use current shift count for both old and new (no change scenario)
                        oldShifts = shiftData.newShifts;
                        newShifts = shiftData.newShifts;
                        newOperationPlanId = currentOperationPlanId;
                    } else {
                        // Fallback: assume 1 shift if unable to determine
                        oldShifts = 1;
                        newShifts = 1;
                        newOperationPlanId = currentOperationPlanId;
                    }
                } catch (error) {
                    console.error('Error fetching shift data:', error);
                    // Fallback: assume 1 shift if error occurs
                    oldShifts = 1;
                    newShifts = 1;
                    newOperationPlanId = program.operationPlanId;
                }
            }
            
            // Navigate to manageShiftsSetup for user to configure shift change options
            const pageReference = {
                type: 'standard__component',
                attributes: {
                    componentName: 'c__manageShiftsSetup'
                },
                state: {
                    c__plantProgramId: plantProgramId,
                    c__oldShifts: oldShifts,
                    c__shopMasterId: shopMasterId,
                    c__programValue: programValue,
                    c__plantName: encodeURIComponent(this.plantName || ''),
                    c__sector: encodeURIComponent(row.authSector || ''),
                    c__productType: encodeURIComponent(row.productType || '')
                }
            };
            
            // Navigate to the component - this will open in a new workspace tab (subtab)
            // Using replace: false ensures it opens as a new tab rather than replacing current
            this[NavigationMixin.Navigate](pageReference, false);
        } catch (error) {
            console.error('Manage Shifts navigation error:', error);
            const errorMessage = error?.body?.message || error?.message || 'Failed to open Manage Shifts. Please try again.';
            this.showToast('Error', errorMessage, 'error');
        }
    }
    
    // Handle close allocate modal
    handleCloseAllocateModal() {
        this.showAllocateModal = false;
        this.allocatePendingShiftChange = null;
    }
    
    // Handle publish success from allocate component
    handleAllocatePublishSuccess() {
        // Refresh the page data after successful publish
        this.dispatchEvent(new RefreshEvent());
    }
    
    // Clear all allocate filters
    clearAllocateFilters() {
        this.allocateFilterFunction = '';
        this.allocateFilterFunctionalArea = '';
        this.allocateFilterClassification = '';
        this.allocateFilterYear = '';
        this.allocateFilterMonth = '';
        this.setupAllocateColumns();
        this.applyAllocateFilters();
    }
    
    // Handle allocate filter changes (same as workbookMonthlyData)
    handleAllocateFilterChange(event) {
        const fieldName = event.target.dataset.field;
        const value = event.target.value;
        
        if (fieldName === 'function') {
            this.allocateFilterFunction = value;
        } else if (fieldName === 'functionalArea') {
            this.allocateFilterFunctionalArea = value;
        } else if (fieldName === 'classification') {
            this.allocateFilterClassification = value;
        } else if (fieldName === 'year') {
            this.allocateFilterYear = value;
        }
        
        this.applyAllocateFilters();
    }
    
    handleAllocateMonthFilterChange(event) {
        this.allocateFilterMonth = event.detail.value;
        this.setupAllocateColumns();
    }
    
    // Apply filters to allocate data (same logic as workbookMonthlyData)
    applyAllocateFilters() {
        if (!this.allocateWorkbookData || this.allocateWorkbookData.length === 0) {
            this.allocateFilteredData = [];
            return;
        }

        const filtered = this.allocateWorkbookData.filter(record => {
            const matchesFunction = !this.allocateFilterFunction || 
                record.FunctionName?.toLowerCase().includes(this.allocateFilterFunction.toLowerCase());
            const matchesFunctionalArea = !this.allocateFilterFunctionalArea || 
                record.FunctionalArea?.toLowerCase().includes(this.allocateFilterFunctionalArea.toLowerCase());
            const matchesClassification = !this.allocateFilterClassification || 
                record.Classification?.toLowerCase().includes(this.allocateFilterClassification.toLowerCase());
            const matchesYear = !this.allocateFilterYear || 
                record.Year === this.allocateFilterYear;
            
            return matchesFunction && matchesFunctionalArea && matchesClassification && matchesYear;
        });
        
        // Create new array with new object references for reactivity
        this.allocateFilteredData = filtered.map(record => ({
            Id: record.Id,
            AuthDBName: record.AuthDBName,
            AuthDBNameLink: record.AuthDBNameLink,
            FunctionalArea: record.FunctionalArea,
            FunctionName: record.FunctionName,
            Classification: record.Classification,
            BaseSupp: record.BaseSupp,
            Year: record.Year,
            Driver: record.Driver,
            PriorMonthTotal: record.PriorMonthTotal,
            ShopMasterView: record.ShopMasterView,
            ChangeLogId: record.ChangeLogId,
            Jan1st: record.Jan1st, Jan2nd: record.Jan2nd, Jan3rd: record.Jan3rd,
            Feb1st: record.Feb1st, Feb2nd: record.Feb2nd, Feb3rd: record.Feb3rd,
            Mar1st: record.Mar1st, Mar2nd: record.Mar2nd, Mar3rd: record.Mar3rd,
            Apr1st: record.Apr1st, Apr2nd: record.Apr2nd, Apr3rd: record.Apr3rd,
            May1st: record.May1st, May2nd: record.May2nd, May3rd: record.May3rd,
            Jun1st: record.Jun1st, Jun2nd: record.Jun2nd, Jun3rd: record.Jun3rd,
            Jul1st: record.Jul1st, Jul2nd: record.Jul2nd, Jul3rd: record.Jul3rd,
            Aug1st: record.Aug1st, Aug2nd: record.Aug2nd, Aug3rd: record.Aug3rd,
            Sep1st: record.Sep1st, Sep2nd: record.Sep2nd, Sep3rd: record.Sep3rd,
            Oct1st: record.Oct1st, Oct2nd: record.Oct2nd, Oct3rd: record.Oct3rd,
            Nov1st: record.Nov1st, Nov2nd: record.Nov2nd, Nov3rd: record.Nov3rd,
            Dec1st: record.Dec1st, Dec2nd: record.Dec2nd, Dec3rd: record.Dec3rd,
            JanTotal: record.JanTotal, FebTotal: record.FebTotal, MarTotal: record.MarTotal,
            AprTotal: record.AprTotal, MayTotal: record.MayTotal, JunTotal: record.JunTotal,
            JulTotal: record.JulTotal, AugTotal: record.AugTotal, SepTotal: record.SepTotal,
            OctTotal: record.OctTotal, NovTotal: record.NovTotal, DecTotal: record.DecTotal
        }));
    }
    
    // Set up columns for allocate modal (same as workbookMonthlyData)
    setupAllocateColumns() {
        const monthOrder = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        
        // Base columns (non-month)
        const baseColumns = [
            { label: 'Function', fieldName: 'FunctionName', type: 'text', editable: false, initialWidth: 150 },
            { label: 'Functional Area', fieldName: 'FunctionalArea', type: 'text', editable: false, initialWidth: 150 },
            { label: 'Classification', fieldName: 'Classification', type: 'text', editable: false, initialWidth: 120 },
            { label: 'Base/Supp', fieldName: 'BaseSupp', type: 'text', editable: false, initialWidth: 100 },
            { label: 'Year', fieldName: 'Year', type: 'text', editable: false, initialWidth: 80 }
        ];
        
        // Determine which shift columns should be editable based on shift transition
        const { oldShifts, newShifts } = this.allocatePendingShiftChange || { oldShifts: 0, newShifts: 0 };
        const is2ndShiftEditable = (oldShifts === 1 && newShifts >= 2) || (oldShifts === 2 && newShifts === 3);
        const is3rdShiftEditable = (oldShifts === 1 && newShifts === 3) || (oldShifts === 2 && newShifts === 3);
        
        // All month column definitions
        const allMonthColumns = [
            { month: 'Jan', label: 'Jan1', fieldName: 'Jan1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jan', label: 'Jan2', fieldName: 'Jan2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jan', label: 'Jan3', fieldName: 'Jan3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Feb', label: 'Feb1', fieldName: 'Feb1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Feb', label: 'Feb2', fieldName: 'Feb2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Feb', label: 'Feb3', fieldName: 'Feb3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Mar', label: 'Mar1', fieldName: 'Mar1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Mar', label: 'Mar2', fieldName: 'Mar2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Mar', label: 'Mar3', fieldName: 'Mar3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Apr', label: 'Apr1', fieldName: 'Apr1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Apr', label: 'Apr2', fieldName: 'Apr2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Apr', label: 'Apr3', fieldName: 'Apr3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'May', label: 'May1', fieldName: 'May1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'May', label: 'May2', fieldName: 'May2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'May', label: 'May3', fieldName: 'May3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jun', label: 'Jun1', fieldName: 'Jun1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jun', label: 'Jun2', fieldName: 'Jun2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jun', label: 'Jun3', fieldName: 'Jun3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jul', label: 'Jul1', fieldName: 'Jul1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jul', label: 'Jul2', fieldName: 'Jul2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Jul', label: 'Jul3', fieldName: 'Jul3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Aug', label: 'Aug1', fieldName: 'Aug1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Aug', label: 'Aug2', fieldName: 'Aug2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Aug', label: 'Aug3', fieldName: 'Aug3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Sep', label: 'Sep1', fieldName: 'Sep1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Sep', label: 'Sep2', fieldName: 'Sep2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Sep', label: 'Sep3', fieldName: 'Sep3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Oct', label: 'Oct1', fieldName: 'Oct1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Oct', label: 'Oct2', fieldName: 'Oct2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Oct', label: 'Oct3', fieldName: 'Oct3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Nov', label: 'Nov1', fieldName: 'Nov1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Nov', label: 'Nov2', fieldName: 'Nov2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Nov', label: 'Nov3', fieldName: 'Nov3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Dec', label: 'Dec1', fieldName: 'Dec1st', type: 'number', editable: false, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Dec', label: 'Dec2', fieldName: 'Dec2nd', type: 'number', editable: is2ndShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
            { month: 'Dec', label: 'Dec3', fieldName: 'Dec3rd', type: 'number', editable: is3rdShiftEditable, sortable: false, hideDefaultActions: true, initialWidth: 60, cellAttributes: { alignment: 'center' }, typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } }
        ];
        
        // Filter month columns based on selected start month
        let filteredMonthColumns = allMonthColumns;
        if (this.allocateFilterMonth) {
            const startMonthIndex = monthOrder.indexOf(this.allocateFilterMonth);
            if (startMonthIndex >= 0) {
                const visibleMonths = monthOrder.slice(startMonthIndex);
                filteredMonthColumns = allMonthColumns.filter(col => visibleMonths.includes(col.month));
            }
        }
        
        // Remove the 'month' property from column definitions
        const cleanedMonthColumns = filteredMonthColumns.map(col => {
            const { month, ...rest } = col;
            return rest;
        });
        
        // Combine base columns with filtered month columns
        this.allocateColumns = [...baseColumns, ...cleanedMonthColumns];
    }
    
    // Handle cell change in allocate modal
    handleAllocateCellChange(event) {
        const newDrafts = event.detail.draftValues;
        
        // Accumulate draft values
        newDrafts.forEach(newDraft => {
            const existingIndex = this.allocateDraftValues.findIndex(d => d.Id === newDraft.Id);
            if (existingIndex >= 0) {
                this.allocateDraftValues[existingIndex] = { ...this.allocateDraftValues[existingIndex], ...newDraft };
            } else {
                this.allocateDraftValues = [...this.allocateDraftValues, newDraft];
            }
        });
        
        // Update the in-memory data for display
        const data = [...this.allocateWorkbookData];
        
        newDrafts.forEach(draft => {
            const record = this.allocateDataMap[draft.Id];
            if (record) {
                Object.assign(record, draft);
                
                // Calculate real-time monthly totals for this record
                const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                months.forEach(month => {
                    const monthLower = month.toLowerCase();
                    const field1st = monthLower + '1st';
                    const field2nd = monthLower + '2nd';
                    const field3rd = monthLower + '3rd';
                    const totalField = month + 'Total';
                    
                    // Use draft values if available, otherwise use original record values
                    const val1st = draft[field1st] !== undefined ? (draft[field1st] || 0) : (record[field1st] || 0);
                    const val2nd = draft[field2nd] !== undefined ? (draft[field2nd] || 0) : (record[field2nd] || 0);
                    const val3rd = draft[field3rd] !== undefined ? (draft[field3rd] || 0) : (record[field3rd] || 0);
                    
                    record[totalField] = val1st + val2nd + val3rd;
                });
                
                const index = data.findIndex(r => r.Id === draft.Id);
                if (index !== -1) {
                    data[index] = record;
                }
            }
        });
        
        this.allocateWorkbookData = data;
        this.applyAllocateFilters();
    }
    
    // Get monthly totals for allocate modal (real-time calculation from draftValues + existing data)
    get allocateMonthlyTotals() {
        if (!this.allocateFilteredData || this.allocateFilteredData.length === 0) {
            return {};
        }
        
        const totals = {};
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        
        // Create a map of draft values by record Id for quick lookup
        const draftMap = {};
        this.allocateDraftValues.forEach(draft => {
            if (draft.Id) {
                draftMap[draft.Id] = draft;
            }
        });
        
        months.forEach(month => {
            const monthLower = month.toLowerCase();
            const field1st = monthLower + '1st';
            const field2nd = monthLower + '2nd';
            const field3rd = monthLower + '3rd';
            
            let total = 0;
            this.allocateFilteredData.forEach(record => {
                const draft = draftMap[record.Id];
                
                // Use draft values if available, otherwise use record values
                const val1st = draft && draft[field1st] !== undefined ? (draft[field1st] || 0) : (record[field1st] || 0);
                const val2nd = draft && draft[field2nd] !== undefined ? (draft[field2nd] || 0) : (record[field2nd] || 0);
                const val3rd = draft && draft[field3rd] !== undefined ? (draft[field3rd] || 0) : (record[field3rd] || 0);
                
                total += val1st + val2nd + val3rd;
            });
            totals[month] = total.toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
        });
        
        return totals;
    }
    
    // Get visible months for allocate modal
    get allocateVisibleMonths() {
        const monthOrder = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        if (!this.allocateFilterMonth) {
            return monthOrder;
        }
        const startIndex = monthOrder.indexOf(this.allocateFilterMonth);
        if (startIndex >= 0) {
            return monthOrder.slice(startIndex);
        }
        return monthOrder;
    }
    
    // Get visible months with totals for template
    get allocateVisibleMonthsWithTotals() {
        return this.allocateVisibleMonths.map(month => ({
            month: month,
            total: this.allocateMonthlyTotals[month] || '0.0'
        }));
    }
    
    // Calculate minimum table width for allocate modal
    get allocateTableMinWidth() {
        const baseWidth = 650; // Base columns width (Row#: 50px + Function: 150px + Functional Area: 150px + Classification: 120px + Base/Supp: 100px + Year: 80px)
        const monthWidth = this.allocateVisibleMonths.length * 180; // 3 columns * 60px each
        return baseWidth + monthWidth;
    }
    
    // Get style string for allocate table width
    get allocateTotalsTableStyle() {
        const width = this.allocateTableMinWidth;
        return `min-width: ${width}px;`;
    }
    
    // Month filter options for allocate modal
    get allocateMonthFilterOptions() {
        return [
            { label: 'All Months', value: '' },
            { label: 'January', value: 'Jan' },
            { label: 'February', value: 'Feb' },
            { label: 'March', value: 'Mar' },
            { label: 'April', value: 'Apr' },
            { label: 'May', value: 'May' },
            { label: 'June', value: 'Jun' },
            { label: 'July', value: 'Jul' },
            { label: 'August', value: 'Aug' },
            { label: 'September', value: 'Sep' },
            { label: 'October', value: 'Oct' },
            { label: 'November', value: 'Nov' },
            { label: 'December', value: 'Dec' }
        ];
    }
    
    // Get unique values for filters
    get allocateUniqueFunctions() {
        if (!this.allocateWorkbookData) return [];
        const functions = [...new Set(this.allocateWorkbookData.map(r => r.FunctionName).filter(Boolean))];
        return functions.sort();
    }
    
    get allocateUniqueFunctionalAreas() {
        if (!this.allocateWorkbookData) return [];
        const areas = [...new Set(this.allocateWorkbookData.map(r => r.FunctionalArea).filter(Boolean))];
        return areas.sort();
    }
    
    get allocateUniqueClassifications() {
        if (!this.allocateWorkbookData) return [];
        const classifications = [...new Set(this.allocateWorkbookData.map(r => r.Classification).filter(Boolean))];
        return classifications.sort();
    }
    
    get allocateUniqueYears() {
        if (!this.allocateWorkbookData) return [];
        const years = [...new Set(this.allocateWorkbookData.map(r => r.Year).filter(Boolean))];
        return years.sort();
    }
    
    get hasAllocateFilteredData() {
        return this.allocateFilteredData && this.allocateFilteredData.length > 0;
    }
    
    @wire(CurrentPageReference)
    getPageReferenceParameters(currentPageReference) {
        if (currentPageReference) {
            console.log(currentPageReference);
            console.log('currentPageReference', JSON.parse(JSON.stringify(currentPageReference)));
            // Use @api recordId if already set, otherwise use currentPageReference.state.recordId
            if (!this.recordId && currentPageReference.state?.recordId) {
                this.recordId = currentPageReference.state.recordId;
            }
            console.log('🔍 Final recordId:', this.recordId);
            if (!this.recordId) {
                console.error('⚠️ recordId is not set! Cannot load initial data.');
                this.error = 'Plant ID is missing. Please ensure you are on a Plant record page.';
                this.isLoading = false;
                return;
            }
            this.loadInitialData();
        }
    }

    async loadInitialData() {
        if (!this.recordId) {
            this.error = 'Plant ID is missing. Please ensure you are on a Plant record page.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.error = null;

        try {
            const data = await getInitialData({ plantId: this.recordId });
            await this.hydrateInitialData(data);
        } catch (error) {
            this.error = error?.body?.message || error?.message || 'Failed to load initial data.';
            console.log('Error', JSON.parse(JSON.stringify(error)));
        } finally {
            this.isLoading = false;
        }
    }

    async hydrateInitialData(data) {
        console.log('📦 RAW DATA FROM APEX:', JSON.parse(JSON.stringify(data)));
        console.log('📦 plantName from Apex:', data.plantName);
        console.log('📦 plantShops count:', data.plantShops?.length);
        console.log('📦 shopMasters count:', data.shopMasters?.length);

        if (data.plantShops) {
            data.plantShops.forEach((ps, idx) => {
                console.log(`📦 PlantShop ${idx}:`, ps.Shop__c, 'Has Plant_Programs__r?', !!ps.Plant_Programs__r);
                if (ps.Plant_Programs__r) {
                    console.log(`   Programs:`, ps.Plant_Programs__r.map(pp => ({
                        Id: pp.Id,
                        Index: pp.Program_Product_Index__c,
                        Program_Code__c: pp.Program_Code__c,
                        Plant_Program_Name__c: pp.Plant_Program_Name__c,
                        Include: pp.Include__c,
                        Shifts_Def__c: pp.Shifts_Def__c
                    })));
                }
            });
        }

        console.log('🔍 Checking plantName in data:', data.plantName);
        this.plantName = data.plantName || '';
        this.plantAuthSector = (data.plantAuthSector || '').trim();
        console.log('🌳 Plant Name set from Apex:', this.plantName);
        console.log('🏭 Plant Auth Sector set from Apex:', this.plantAuthSector);

        if (!this.plantName && this.recordId) {
            console.warn('⚠️ plantName is empty from Apex. RecordId:', this.recordId);
        }

        this.plantShops = data.plantShops || [];
        this.shopMasters = data.shopMasters || [];
        this.shopPrograms = data.shopPrograms || [];
        this.programMasters = data.programMasters || [];
        this.childProgramsMap = {};
        this.expandedRows = new Set();

        console.log('📦 programMasters count:', this.programMasters?.length);
        if (this.programMasters && this.programMasters.length > 0) {
            console.log('📦 Sample Program Master:', JSON.parse(JSON.stringify(this.programMasters[0])));
        }

        this.originalPlantProgramIds = new Set(data.originalPlantProgramIds || []);
        await this.preloadProgramCodeOptionsFromProgramMasters();

        let { plantShopKeysMap, plantShopRows } = this.populateDefaultPlantShopRows();

        console.log('plantShopKeysMap', JSON.parse(JSON.stringify(plantShopKeysMap)));
        console.log('plantShopRows', JSON.parse(JSON.stringify(plantShopRows)));

        plantShopRows = this.populatePlantShopRows(plantShopRows, plantShopKeysMap);
        console.log('plantShopRows after processing', JSON.parse(JSON.stringify(plantShopRows)));

        this.plantShopRows = plantShopRows.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
        console.log('plantShopRows after sort', JSON.parse(JSON.stringify(this.plantShopRows)));

        this.hasExistingPlantPrograms = this.plantShopRows.some(row =>
            row.programLoop.some(prog => prog.plantProgramId)
        );
        console.log('hasExistingPlantPrograms:', this.hasExistingPlantPrograms);

        this.originalPlantShopRows = JSON.parse(JSON.stringify(this.plantShopRows));
        this.hasUnsavedChanges = false;
        this.pendingEquationReparentRequests = [];
        this.reloadProgramCodesAfterPlantNameLoad();

        if (this.plantShopRows.length > 0) {
            const firstRow = this.plantShopRows[0];
            console.log('🔍 First row program codes:', JSON.stringify(firstRow.programLoop.map(p => ({
                programValue: p.programValue,
                programCode: p.programCode,
                programName: p.programName,
                isVisible: p.isVisible,
                showDropdown: p.showDropdown,
                plantProgramId: p.plantProgramId
            })), null, 2));
            console.log('🔍 First row details:', {
                authSector: firstRow.authSector,
                productType: firstRow.productType,
                shop: firstRow.shop
            });
        }
    }


    async handleOperationPlanDropdownChange(event) {
        console.log('🔵 handleOperationPlanDropdownChange CALLED!');
        console.log('Event:', event);
        console.log('Event detail:', event.detail);
        console.log('Event target:', event.target);
        console.log('Event target dataset:', event.target.dataset);
        
        const { key: shopMasterId, program: programValue } = event.target.dataset;
        const newOperationPlanId = event.detail.value;
        
        // Call the existing handler logic
        await this.handleOperationPlanChangeInternal(shopMasterId, programValue, newOperationPlanId);
    }
    
    async handleOperationPlanChange(event) {
        console.log('🔵 handleOperationPlanChange CALLED!');
        console.log('Event:', event);
        console.log('Event detail:', event.detail);
        console.log('Event target:', event.target);
        console.log('Event target dataset:', event.target.dataset);
        
        const { key: shopMasterId, program: programValue } = event.target.dataset;
        const newOperationPlanId = event.detail.recordId;
        
        // Call the existing handler logic
        await this.handleOperationPlanChangeInternal(shopMasterId, programValue, newOperationPlanId);
    }
    
    async handleOperationPlanChangeInternal(shopMasterId, programValue, newOperationPlanId) {
        
        console.log('=== handleOperationPlanChange called ===');
        console.log('Selected Operation Plan ID:', newOperationPlanId);
        console.log('Shop Master ID:', shopMasterId);
        console.log('Program Value:', programValue);
        console.log('Current plantShopRows:', JSON.parse(JSON.stringify(this.plantShopRows)));

        const plantShops = this.plantShopRows;
        const plantShop = plantShops.find(r => r.key === shopMasterId);
        if (!plantShop) {
            console.warn(`[handleOperationPlanChange] Row not found for key: ${shopMasterId}`);
            return;
        }

        const program = plantShop.programLoop.find(p => p.programValue === programValue);
        
        // Store the original Operation Plan ID (before any changes) for shift comparison
        const originalOperationPlanId = program.originalOperationPlanId || program.operationPlanId;
        const currentOperationPlanId = program.operationPlanId;
        
        console.log('Current Operation Plan ID:', currentOperationPlanId);
        console.log('Original Operation Plan ID:', originalOperationPlanId);
        console.log('New Operation Plan ID:', newOperationPlanId);
        console.log('Program plantProgramId:', program.plantProgramId);
        console.log('Program isChanged before update:', program.isChanged);

        // Check if shift count changed (compare new selection against original, not current)
        const shouldCheckShiftChange = originalOperationPlanId && newOperationPlanId && 
                                      originalOperationPlanId !== newOperationPlanId;
        
        if (shouldCheckShiftChange) {
            console.log('🔍 Checking shift change...');
            console.log('  Original Op Plan ID:', originalOperationPlanId);
            console.log('  New Op Plan ID:', newOperationPlanId);
            
            try {
                console.log('Calling getOperationPlanShifts with params:', {
                    oldOpPlanId: originalOperationPlanId,
                    newOpPlanId: newOperationPlanId
                });
                
                // Query both Operation Plans to get shift counts (use original, not current)
                const shiftData = await getOperationPlanShifts({ 
                    oldOpPlanId: originalOperationPlanId, 
                    newOpPlanId: newOperationPlanId 
                });
                
                console.log('📊 Shift Data Response:', shiftData ? JSON.parse(JSON.stringify(shiftData)) : 'NULL');
                
                if (!shiftData) {
                    console.error('❌ Shift data is null or undefined');
                    throw new Error('No shift data returned from server');
                }
                
                const oldShifts = shiftData.oldShifts || 0;
                const newShifts = shiftData.newShifts || 0;
                
                console.log('  Old Shifts:', oldShifts);
                console.log('  New Shifts:', newShifts);
                
                // If shifts increased (e.g., 2 → 3), show Allocate button
                if (newShifts > oldShifts) {
                    console.log('🔔 Shift increase detected:', oldShifts, '→', newShifts);
                    this.oldShiftCount = oldShifts;
                    this.newShiftCount = newShifts;
                    this.auth3rdShiftValue = 0; // Reset
                    
                    // Get the Plant Program ID from the program (may be null if not saved yet)
                    const plantProgramId = program.plantProgramId;
                    console.log('Plant Program ID:', plantProgramId);
                    
                    // Store shift change info for Allocate button (even if plantProgramId is null)
                    this.allocatePendingShiftChange = {
                        shopMasterId,
                        programValue,
                        newOperationPlanId,
                        plantProgramId: plantProgramId || null, // Allow null - will be checked when clicking Allocate
                        oldShifts,
                        newShifts
                    };
                    
                    // Update the program to show the Allocate button as soon as Op Plan Default changes
                    // Show Allocate button if operation plan is selected, even if plantProgramId doesn't exist yet
                    this.plantShopRows = this.plantShopRows.map(row => {
                        if (row.key === shopMasterId) {
                            const isMasterRow = this.shouldExpandShop(row.authSector, row.productType, row.shop) !== null;
                            return {
                                ...row,
                                programLoop: row.programLoop.map(prog => {
                                    if (prog.programValue === programValue) {
                                        const originalId = prog.originalOperationPlanId || prog.operationPlanId;
                                        const updatedProg = {
                                            ...prog,
                                            operationPlanId: newOperationPlanId,
                                            originalOperationPlanId: originalId,
                                            isChanged: true,
                                            isProgramDetailChanged: true,
                                            isOpPlanReadOnly: !!newOperationPlanId,
                                            shiftChangeInfo: {
                                                oldShifts,
                                                newShifts,
                                                plantProgramId: plantProgramId || null,
                                                newOperationPlanId
                                            }
                                        };
                                        // Include row-level properties for shouldShowAllocateButton debug logging
                                        // Show Allocate button when Program Code, Program Name, and Op Plan all have values
                                        updatedProg.showAllocateButton = this.shouldShowAllocateButton({
                                            ...updatedProg,
                                            authSector: row.authSector,
                                            productType: row.productType,
                                            shop: row.shop
                                        }, isMasterRow);
                                        return updatedProg;
                                    }
                                    return prog;
                                })
                            };
                        }
                        return row;
                    });
                    
                    // Mark as having unsaved changes
                    this.hasUnsavedChanges = true;
                    
                    console.log('✅ Shift change detected - Allocate button should be visible');
                    return; // Don't update operation plan yet, wait for Allocate button click
                }
            } catch (error) {
                console.error('❌ Error checking shift changes:', error);
                console.error('Error message:', error.message);
                console.error('Error body:', error.body);
                console.error('Full error:', JSON.stringify(error, null, 2));
                
                const errorMessage = error.body?.message || error.message || 'Unknown error';
                this.showToast('Error', 'Failed to check shift changes: ' + errorMessage, 'error');
            }
        } else {
            console.log('⏭️ Skipping shift check - same Operation Plan or missing IDs');
        }

        // No shift change or shift decrease, just update
        console.log('Updating operation plan without shift increase modal');
        console.log('BEFORE UPDATE - program.operationPlanId:', program.operationPlanId);
        console.log('BEFORE UPDATE - program.isChanged:', program.isChanged);
        console.log('BEFORE UPDATE - program.plantProgramId:', program.plantProgramId);
        
        // Force reactivity by creating a new array with properly updated nested objects
        this.plantShopRows = plantShops.map(row => {
            if (row.key === shopMasterId) {
                console.log('Updating row for key:', shopMasterId);
                const isMasterRow = this.shouldExpandShop(row.authSector, row.productType, row.shop) !== null;
                // Deep clone the row and update the specific program
                return {
                    ...row,
                    programLoop: row.programLoop.map(prog => {
                        if (prog.programValue === programValue) {
                            console.log('Updating program:', programValue);
                            console.log('Setting operationPlanId from', prog.operationPlanId, 'to', newOperationPlanId);
                            // Create new program object with updated values
                            // Store original if not already stored
                            const originalId = prog.originalOperationPlanId || prog.operationPlanId;
                            const updatedProg = {
                                ...prog,
                                operationPlanId: newOperationPlanId,
                                originalOperationPlanId: originalId, // Keep track of original for shift comparison
                                isChanged: true,
                                isProgramDetailChanged: true,
                                isOpPlanReadOnly: !!newOperationPlanId
                            };
                            // Include row-level properties for shouldShowAllocateButton debug logging
                            updatedProg.showAllocateButton = this.shouldShowAllocateButton({
                                ...updatedProg,
                                authSector: row.authSector,
                                productType: row.productType,
                                shop: row.shop
                            }, isMasterRow);
                            return updatedProg;
                        }
                        return prog;
                    })
                };
            }
            return row;
        });
        
        // Mark as having unsaved changes
        this.hasUnsavedChanges = true;
    }
    
    /**
     * Finds the parent accordion row for a given child shop
     * For Assembly-Vehicle shops (except Body/Paint), returns the "All Except Body, Paint" row
     * For other sectors, returns the "All" row if it exists
     */
    findParentAccordionRow(childRow) {
        const sector = childRow.authSector || '';
        const productType = childRow.productType || '';
        const shop = childRow.shop || '';
        
        // Skip if this is already a parent row (Body, Paint, or accordion rows)
        if (shop === 'Body' || shop === 'Paint' || isShopAll(shop) || isShopAllExceptBodyPaint(shop)) {
            return null;
        }
        
        // For Assembly-Vehicle child shops, find "All Except Body, Paint" parent
        if (sector === 'Assembly' && productType === 'Vehicle') {
            return this.plantShopRows.find(r => 
                r.authSector === sector && 
                r.productType === productType && 
                isShopAllExceptBodyPaint(r.shop)
            );
        }
        
        // For other sectors, find "All" parent if it exists
        return this.plantShopRows.find(r => 
            r.authSector === sector && 
            r.productType === productType && 
            isShopAll(r.shop) &&
            r.isExpandable
        );
    }
    
    /**
     * Syncs program code/name changes from child shops to parent accordion row
     */
    syncParentRowFromChild(childRow, programValue, programCode, programName) {
        const parentRow = this.findParentAccordionRow(childRow);
        if (!parentRow) {
            return; // No parent row to sync to
        }
        
        const parentProgram = parentRow.programLoop.find(p => p.programValue === programValue);
        if (!parentProgram) {
            return; // Parent doesn't have this program index
        }
        
        // Update parent row's program code and name to match child
        // Only update if child has a value
        if (programCode) {
            parentProgram.programCode = programCode;
            parentProgram.selectedProgramCode = programCode;
        }
        if (programName) {
            parentProgram.programName = programName;
            parentProgram.plantProgramName = programName;
        }
        
        // Recalculate showAllocateButton for parent
        const isMasterRow = this.shouldExpandShop(parentRow.authSector, parentRow.productType, parentRow.shop) !== null;
        parentProgram.showAllocateButton = this.shouldShowAllocateButton(parentProgram, isMasterRow);
        
        // Mark parent as changed
        parentProgram.isChanged = true;
        this.hasUnsavedChanges = true;
        
        // Force reactivity
        this.plantShopRows = [...this.plantShopRows];
    }
    
    handlePlantProgramNameChange(event) {
        const { key: shopMasterId, program: programValue } = event.target.dataset;
        const newName = event.detail.value;
        
        console.log(`[handlePlantProgramNameChange] Updating ${shopMasterId} - ${programValue}: ${newName}`);
        
        const plantShops = this.plantShopRows;
        const plantShop = plantShops.find(r => r.key === shopMasterId);
        if (!plantShop) {
            console.warn(`[handlePlantProgramNameChange] Row not found for key: ${shopMasterId}`);
            return;
        }

        const program = plantShop.programLoop.find(p => p.programValue === programValue);
        if (!program) {
            console.warn(`[handlePlantProgramNameChange] Program not found in row ${shopMasterId} for value: ${programValue}`);
            return;
        }
        
        // Update plant program name with proper reactivity
        // Force reactivity by creating a completely new array
        this.plantShopRows = [...plantShops.map(row => {
            if (row.key === shopMasterId) {
                return {
                    ...row,
                    programLoop: [...row.programLoop.map(prog => {
                        if (prog.programValue === programValue) {
                            const isMasterRow = this.shouldExpandShop(row.authSector, row.productType, row.shop) !== null;
                            // Include row-level properties for shouldShowAllocateButton calculation
                            const shouldShow = this.shouldShowAllocateButton({
                                ...prog,
                                plantProgramName: newName || '',
                                authSector: row.authSector,
                                productType: row.productType,
                                shop: row.shop
                            }, isMasterRow);
                            const updatedProg = {
                                ...prog,
                                plantProgramName: newName || '',
                                isChanged: true,
                                isProgramDetailChanged: true,
                                showAllocateButton: shouldShow // Set directly in object literal
                            };
                            return updatedProg;
                        }
                        return { ...prog };
                    })]
                };
            }
            return { ...row };
        })];
        
        // Sync to parent accordion row if this is a child shop
        this.syncParentRowFromChild(plantShop, programValue, program.selectedProgramCode, newName);
        
        // Mark as having unsaved changes
        this.hasUnsavedChanges = true;
        
        // Force reactivity by reassigning the array reference
        this.plantShopRows = [...this.plantShopRows];
    }

    async handleProgramChange(event) {
        const { key: shopMasterId, program: programValue } = event.target.dataset;
        const userInput = event.target.checked;

        console.log(`[handleProgramChange] Updating ${shopMasterId} - ${programValue}: ${userInput}`);

        const plantShops = this.plantShopRows;
        const plantShop = plantShops.find(r => r.key === shopMasterId);

        if (!plantShop) {
            console.warn(`[updateProgramState] Row not found for key: ${shopMasterId}`);
            return;
        }

        const program = (plantShop.programLoop || []).find(p => p.programValue === programValue);
        if (!program) {
            console.warn(`[updateProgramState] Program not found in row ${shopMasterId} for value: ${programValue}`);
            return;
        }
        console.log('plantShop', JSON.parse(JSON.stringify(plantShop)));
        console.log('program', JSON.parse(JSON.stringify(program)));

        if (!userInput && program.plantProgramId) {
            await this.openDeactivateProgramModal(plantShop, program);
            return;
        }

        if (userInput && program.plantProgramId) {
            this.pendingEquationReparentRequests = this.pendingEquationReparentRequests.filter(
                (request) => request.sourcePlantProgramId !== program.plantProgramId
            );
        }

        await this.applyProgramSelectionState(shopMasterId, programValue, userInput, {
            authSector: plantShop.authSector,
            productType: plantShop.productType,
            selectedProgramCode: program.selectedProgramCode || program.programCode || ''
        });
    }

    async applyProgramSelectionState(shopMasterId, programValue, userInput, context = {}) {
        console.log('User Input Prevail');
        this.plantShopRows = this.plantShopRows.map(row => {
            if (row.key === shopMasterId) {
                const isMasterRow = this.shouldExpandShop(row.authSector, row.productType, row.shop) !== null;
                const updatedRow = {
                    ...row,
                    programLoop: row.programLoop.map(prog => {
                        if (prog.programValue === programValue) {
                            if (userInput) {
                                // Re-selecting: do not restore any values
                                const updated = {
                                    ...prog,
                                    isSelected: true,
                                    isChanged: true,
                                    isIncludeChanged: true
                                };
                                updated.showAllocateButton = this.shouldShowAllocateButton(updated, isMasterRow);
                                return updated;
                            }
                            // Deselecting: clear UI values, make Op Plan editable
                            return {
                                ...prog,
                                isSelected: false,
                                isChanged: true,
                                isIncludeChanged: true,
                                showAllocateButton: false,
                                isOpPlanReadOnly: false,
                                selectedProgramCode: '',
                                plantProgramName: '',
                                operationPlanId: ''
                            };
                        }
                        return prog;
                    })
                };
                // Propagate value clearing to child rows when deselecting (do not restore on re-select)
                if (!userInput && updatedRow.childRows) {
                    updatedRow.childRows = updatedRow.childRows.map(childRow => ({
                        ...childRow,
                        programList: childRow.programList.map(cp => {
                            if (cp.programIndex === programValue) {
                                return {
                                    ...cp,
                                    programCode: '',
                                    operationPlanId: '',
                                    isOpPlanReadOnly: false
                                };
                            }
                            return cp;
                        })
                    }));
                }
                return updatedRow;
            }
            return row;
        });

        if (userInput) {
            const programCode = context.selectedProgramCode || '';
            if (programCode && context.authSector && context.productType) {
                this.ensurePlantProgramCodeRecord(context.authSector, context.productType, programCode);
            }
        }

        this.hasUnsavedChanges = true;
    }

    async openDeactivateProgramModal(plantShop, program) {
        const existingRequest = this.pendingEquationReparentRequests.find(
            (request) => request.sourcePlantProgramId === program.plantProgramId
        );
        const shopOptions = await this.getApplicableReplacementShopOptions(plantShop);
        const isShopSelectable = isShopAll(plantShop.shop) || isShopAllExceptBodyPaint(plantShop.shop);
        const defaultShopMasterId = existingRequest?.shopMasterId ||
            (isShopSelectable ? shopOptions[0]?.value || '' : plantShop.shopMasterId);

        this.deactivateProgramModalState = {
            sourcePlantProgramId: program.plantProgramId,
            sourceShopMasterId: plantShop.shopMasterId,
            sourceProgramIndex: program.programValue,
            authSector: plantShop.authSector,
            productType: plantShop.productType,
            sourceShopLabel: plantShop.shop,
            shopMasterId: defaultShopMasterId,
            shopOptions,
            isShopSelectable,
            programCodeOptions: this.getProgramDropdownOptions(plantShop.authSector, plantShop.productType),
            programCode: existingRequest?.programCode || program.selectedProgramCode || program.programCode || '',
            programName: existingRequest?.programName || program.plantProgramName || program.programName || '',
            operationPlanId: existingRequest?.operationPlanId || program.operationPlanId || '',
            programIndex: existingRequest?.programIndex || program.programValue || 'A'
        };
        this.showDeactivateProgramModal = true;
    }

    handleDeactivateProgramModalFieldChange(event) {
        const fieldName = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value ?? '';
        this.deactivateProgramModalState = {
            ...this.deactivateProgramModalState,
            [fieldName]: value
        };
    }

    handleCloseDeactivateProgramModal() {
        this.showDeactivateProgramModal = false;
        this.deactivateProgramModalState = null;
    }

    async handleConfirmDeactivateProgramModal() {
        const modalState = this.deactivateProgramModalState;
        if (!modalState) {
            return;
        }

        if (!modalState.shopMasterId || !modalState.programCode || !modalState.programName ||
            !modalState.operationPlanId || !modalState.programIndex) {
            this.showToast('Error', 'Complete all replacement Plant Program fields before continuing.', 'error');
            return;
        }

        if (modalState.shopMasterId === modalState.sourceShopMasterId &&
            modalState.programIndex === modalState.sourceProgramIndex) {
            this.showToast(
                'Error',
                'Choose a different Program Index or a different Shop for the replacement Plant Program.',
                'error'
            );
            return;
        }

        const request = {
            sourcePlantProgramId: modalState.sourcePlantProgramId,
            plantId: this.recordId,
            sector: modalState.authSector,
            productType: modalState.productType,
            shopMasterId: modalState.shopMasterId,
            programCode: modalState.programCode,
            programName: modalState.programName,
            operationPlanId: modalState.operationPlanId,
            programIndex: modalState.programIndex
        };

        this.isLoading = true;
        try {
            const result = await reparentEquationFunctionsForDeactivatedPrograms({
                requestsJson: JSON.stringify([request])
            });

            this.handleCloseDeactivateProgramModal();
            await this.loadInitialData();
            this.dispatchEvent(new RefreshEvent());
            this.showToast('Success', result?.message || 'Program deactivated and functions reparented successfully.', 'success');
        } catch (error) {
            const errorMessage = error?.body?.message || error?.message || 'Failed to deactivate program.';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async getApplicableReplacementShopOptions(plantShop) {
        const shopNorm = (plantShop.shop || '').trim();

        if (isShopAll(shopNorm) || isShopAllExceptBodyPaint(shopNorm)) {
            const childRowOptions = (plantShop.childRows || [])
                .filter((childRow) => childRow?.shop && childRow?.shopMasterId)
                .map((childRow) => ({
                    label: childRow.shop,
                    value: childRow.shopMasterId
                }));

            if (childRowOptions.length > 0) {
                return childRowOptions;
            }

            const expansionCriteria = this.shouldExpandShop(plantShop.authSector, plantShop.productType, plantShop.shop);
            if (expansionCriteria) {
                try {
                    const matchingShops = await getShopMastersByCriteria({
                        sector: plantShop.authSector,
                        productType: plantShop.productType,
                        excludeShops: expansionCriteria.excludeShops
                    });

                    return (matchingShops || []).map((shopMaster) => ({
                        label: shopMaster.Shop__c,
                        value: shopMaster.Id
                    }));
                } catch (error) {
                    console.error('Error loading replacement shop options:', error);
                }
            }
        }

        const matchingShops = this.getShopsForSectorProductType(plantShop.authSector, plantShop.productType);

        // Mirror managePlantShopsV2 accordion expansion rules:
        // - If current row is "All", offer all child shops except "All"
        // - If current row is "All Except Body, Paint", offer only remaining shops (exclude Body/Paint + the accordion shop itself)
        const excludedShops = new Set();
        if (isShopAll(shopNorm)) {
            excludedShops.add(SHOP_ALL);
        } else if (isShopAllExceptBodyPaint(shopNorm)) {
            excludedShops.add(SHOP_ALL_EXCEPT_BODY_PAINT);
            excludedShops.add(SHOP_ALL_EXCEPT_BODY_PAINT_ALT);
            excludedShops.add('Body');
            excludedShops.add('Paint');
        } else {
            // For safety, keep out special accordion rows
            excludedShops.add(SHOP_ALL);
            excludedShops.add(SHOP_ALL_EXCEPT_BODY_PAINT);
            excludedShops.add(SHOP_ALL_EXCEPT_BODY_PAINT_ALT);
        }

        return matchingShops
            .filter((shopMaster) => !excludedShops.has((shopMaster.Shop__c || '').trim()))
            .map((shopMaster) => ({
                label: shopMaster.Shop__c,
                value: shopMaster.Id
            }));
    }

    get isDeactivateProgramConfirmDisabled() {
        const modalState = this.deactivateProgramModalState;
        if (!modalState) {
            return true;
        }

        const missingRequiredValue = !modalState.shopMasterId || !modalState.programCode ||
            !modalState.programName || !modalState.operationPlanId || !modalState.programIndex;
        const sameProgramSlot = modalState.shopMasterId === modalState.sourceShopMasterId &&
            modalState.programIndex === modalState.sourceProgramIndex;

        return missingRequiredValue || sameProgramSlot;
    }

    get programIndexOptions() {
        return (this.programValues || []).map((programValue) => ({
            label: programValue,
            value: programValue
        }));
    }

    async processPendingEquationReparenting() {
        if (!this.pendingEquationReparentRequests || this.pendingEquationReparentRequests.length === 0) {
            return;
        }

        await reparentEquationFunctionsForDeactivatedPrograms({
            requestsJson: JSON.stringify(this.pendingEquationReparentRequests)
        });
    }

    handleProgramCodeChange(event) {
        const { key: shopMasterId, program: programValue } = event.target.dataset;
        const selectedValue = event.detail.value;

        console.log(`[handleProgramCodeChange] Updating ${shopMasterId} - ${programValue}: ${selectedValue}`);

        const plantShops = this.plantShopRows;
        const plantShop = plantShops.find(r => r.key === shopMasterId);

        if (!plantShop) {
            console.warn(`[handleProgramCodeChange] Row not found for key: ${shopMasterId}`);
            return;
        }

        const program = (plantShop.programLoop || []).find(p => p.programValue === programValue);
        if (!program) {
            console.warn(`[handleProgramCodeChange] Program not found in row ${shopMasterId} for value: ${programValue}`);
            return;
        }

        // Update selected program code with proper reactivity
        // Force reactivity by creating a completely new array
        this.plantShopRows = [...plantShops.map(row => {
            if (row.key === shopMasterId) {
                return {
                    ...row,
                    programLoop: [...row.programLoop.map(prog => {
                        if (prog.programValue === programValue) {
                            const isMasterRow = this.shouldExpandShop(row.authSector, row.productType, row.shop) !== null;
                            // Include row-level properties for shouldShowAllocateButton calculation
                            const shouldShow = this.shouldShowAllocateButton({
                                ...prog,
                                selectedProgramCode: selectedValue,
                                programCode: selectedValue,
                                authSector: row.authSector,
                                productType: row.productType,
                                shop: row.shop
                            }, isMasterRow);
                            const updatedProgram = {
                                ...prog,
                                selectedProgramCode: selectedValue,
                                programCode: selectedValue,
                                isChanged: true,
                                isProgramDetailChanged: true,
                                showAllocateButton: shouldShow
                            };
                            return updatedProgram;
                        }
                        return { ...prog };
                    })]
                };
            }
            return { ...row };
        })];
        
        // If checkbox is checked and program code is populated, ensure Plant_Program_Code__c record exists
        if (program.isSelected && selectedValue && plantShop.authSector && plantShop.productType) {
            this.ensurePlantProgramCodeRecord(plantShop.authSector, plantShop.productType, selectedValue);
        }
        
        // Sync to parent accordion row if this is a child shop
        this.syncParentRowFromChild(plantShop, programValue, selectedValue, program.plantProgramName);
        
        // Mark as having unsaved changes
        this.hasUnsavedChanges = true;
        
        // Force reactivity by reassigning the array reference
        this.plantShopRows = [...this.plantShopRows];
    }

    /**
     * Returns true if the only changes are Include__c checkbox toggles (uncheck/recheck).
     * When true, we use a minimal save path that ONLY updates Include__c - no Plant_Function__c
     * updates, no expansion, no Allocation_Database__c creation.
     */
    isIncludeOnlyChange() {
        let hasAnyChange = false;
        let hasNonIncludeChange = false;
        for (const row of this.plantShopRows || []) {
            for (const program of row.programLoop || []) {
                if (!program.isVisible || !program.isChanged) continue;
                hasAnyChange = true;
                // New program (would create Plant_Function__c -> Allocation_Database__c)
                if (!program.plantProgramId && program.isSelected) {
                    hasNonIncludeChange = true;
                    break;
                }
                // Program Code, Name, or Operation Plan was changed
                if (program.isProgramDetailChanged) {
                    hasNonIncludeChange = true;
                    break;
                }
                // Shift values from Allocate modal (would update Plant_Function__c)
                if ((program.workbookShiftValues && Object.keys(program.workbookShiftValues).length > 0) ||
                    (program.workbookShift2ndValues && Object.keys(program.workbookShift2ndValues).length > 0) ||
                    (program.functionShiftValues && Object.keys(program.functionShiftValues).length > 0) ||
                    (program.functionShift2ndValues && Object.keys(program.functionShift2ndValues).length > 0)) {
                    hasNonIncludeChange = true;
                    break;
                }
            }
            if (hasNonIncludeChange) break;
        }
        return hasAnyChange && !hasNonIncludeChange;
    }

    /**
     * Minimal save path: ONLY updates Include__c on Plant_Program__c.
     * No Plant_Function__c updates, no expansion, no Allocation_Database__c creation.
     */
    async handleSaveIncludeOnly() {
        const plantId = this.recordId;
        if (!plantId) {
            this.showToast('Error', 'Plant ID is required', 'error');
            return;
        }
        await this.propagateIncludeFalseForMasterRows();
        await this.propagateIncludeTrueForMasterRows();
        // Regular (non-master) rows: update by plantProgramId
        const uncheckedIds = [];
        const checkedIds = [];
        const shopNorm = (s) => (s || '').trim();
        const isMasterRow = (row) => isShopAll(shopNorm(row.shop)) || isShopAllExceptBodyPaint(shopNorm(row.shop));
        for (const row of this.plantShopRows || []) {
            if (isMasterRow(row)) continue; // Already handled by propagate
            for (const program of row.programLoop || []) {
                if (!program.isVisible || !program.isChanged || !program.plantProgramId) continue;
                if (program.isSelected) {
                    checkedIds.push(program.plantProgramId);
                } else {
                    uncheckedIds.push(program.plantProgramId);
                }
            }
        }
        if (uncheckedIds.length > 0) {
            await updatePlantProgramsIncludeAndAuth({ plantId, plantProgramIds: uncheckedIds, includeValue: false });
        }
        if (checkedIds.length > 0) {
            await updatePlantProgramsIncludeAndAuth({ plantId, plantProgramIds: checkedIds, includeValue: true });
        }
        await this.processPendingEquationReparenting();
    }

    async handleSave() {
        try {
            this.isLoading = true;

            // When ONLY Include__c checkbox toggles: use minimal path to avoid creating Allocation_Database__c
            if (this.isIncludeOnlyChange()) {
                await this.handleSaveIncludeOnly();
                this.childProgramsMap = {};
                this.expandedRows = new Set();
                this.plantShopRows = this.plantShopRows.map(r => ({
                    ...r,
                    childRows: undefined,
                    isExpanded: false,
                    programLoop: (r.programLoop || []).map(prog => ({
                        ...prog,
                        isChanged: false,
                        isIncludeChanged: false,
                        isProgramDetailChanged: false
                    }))
                }));
                this.hasUnsavedChanges = false;
                this.pendingEquationReparentRequests = [];
                this.originalPlantShopRows = JSON.parse(JSON.stringify(this.plantShopRows));
                this.dispatchEvent(new RefreshEvent());
                this.dispatchEvent(new CloseActionScreenEvent());
                this.showToast('Success', 'Records saved successfully', 'success');
                this.isLoading = false;
                return;
            }

            // 0. Handle special shop combinations that need expansion
            const expandedShopResult = await this.handleSpecialShopCombinations();
            const expandedShopDataMap = expandedShopResult.expandedShopDataMap || {};
            const expandedInsertResult = expandedShopResult.insertResult || { shopMasterIdToPlantShopIdMap: {} };

            // 1. Prepare and insert new Plant Shops if needed (excluding expanded shops which are already inserted)
            const shopDataList = this.prepareShopDataList(expandedShopDataMap);
            const insertResult = await this.insertPlantShopsIfNeeded(shopDataList);
            
            // Merge expanded shop mappings into insertResult
            if (expandedInsertResult.shopMasterIdToPlantShopIdMap) {
                insertResult.shopMasterIdToPlantShopIdMap = insertResult.shopMasterIdToPlantShopIdMap || {};
                Object.assign(insertResult.shopMasterIdToPlantShopIdMap, expandedInsertResult.shopMasterIdToPlantShopIdMap);
            }

            // 2. Prepare Program Data List for Saving (with expanded shops)
            const programDataList = await this.prepareProgramDataList(insertResult, expandedShopDataMap);
            
            if (!programDataList || programDataList.length === 0) {
                this.showToast('Warning', 'No changes detected to save', 'warning');
                this.isLoading = false;
                return;
            }

            // 3. Save Programs
            const saveResult = await savePrograms({ programDataListString: JSON.stringify(programDataList) });

            // 4. Create Plant Functions for new programs
            await this.handleCreatePlantFunctions(saveResult);
            
            // 5. Propagate Operation Plan changes for special shop combinations
            await this.propagateOperationPlanForSpecialShops();

            // 8. When checkbox unchecked on master row (All or All Except Body, Paint), set Include__c=false for all matching programs (except Assembly-Vehicle-Body and Assembly-Vehicle-Paint)
            await this.propagateIncludeFalseForMasterRows();

            // 8b. When checkbox checked again on master row, set Include__c=true for all matching programs (cascade to child shops)
            await this.propagateIncludeTrueForMasterRows();

            // 9. Propagate Program Code/Name changes for special shop combinations (cascade to child shops)
            await this.propagateProgramCodeAndNameForSpecialShops();

            // 10. Reparent Equation plant functions for the programs being deactivated in this save
            await this.processPendingEquationReparenting();

            // Clear cached child accordion data so next expand fetches fresh Plant_Program__c
            this.childProgramsMap = {};
            this.expandedRows = new Set();
            this.plantShopRows = this.plantShopRows.map(r => ({
                ...r,
                childRows: undefined,
                isExpanded: false,
                programLoop: (r.programLoop || []).map(prog => ({
                    ...prog,
                    isChanged: false,
                    isIncludeChanged: false,
                    isProgramDetailChanged: false
                }))
            }));
            this.hasUnsavedChanges = false;
            this.pendingEquationReparentRequests = [];
            this.originalPlantShopRows = JSON.parse(JSON.stringify(this.plantShopRows));

            // 11. Refresh and Close
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(new CloseActionScreenEvent());

            // Show Success Toast
            this.showToast('Success', 'Records saved successfully', 'success');

        } catch (error) {
            console.error('Save error:', error?.body?.message || error?.message || 'An error occurred during save');
            const errorMessage = error?.body?.message || error?.message || 'An error occurred during save';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Save programs without closing the quick action (used when opening Allocate page)
     * @param {String} shopMasterId - Shop Master ID to find the program
     * @param {String} programValue - Program Value to find the program
     * @returns {Promise<Object>} Result object with success flag and plantProgramId if successful
     */
    async handleSaveForAllocate(shopMasterId, programValue) {
        try {
            this.isLoading = true;

            // Find the specific program that was changed
            const row = this.plantShopRows.find(r => r.key === shopMasterId);
            if (!row) {
                return { success: false, errorMessage: 'Row not found' };
            }
            
            const program = row.programLoop.find(p => p.programValue === programValue);
            if (!program) {
                return { success: false, errorMessage: 'Program not found' };
            }
            
            // OPTIMIZATION: If Plant Program already exists and only Op Plan Default changed,
            // use the optimized single-update method instead of processing everything
            if (program.operationPlanId) {
                // Get values from row and program
                const plantId = this.recordId;
                const authSector = row.authSector;
                const productType = row.productType;
                const shop = row.shop;
                const programCode = program.selectedProgramCode || program.programCode || '';
                const programIndex = program.programValue;
                const operationPlanId = program.operationPlanId;
                
                console.log('Using optimized single Plant Program update by matching fields:', {
                    plantId: plantId,
                    authSector: authSector,
                    productType: productType,
                    programCode: programCode,
                    shop: shop,
                    programIndex: programIndex,
                    operationPlanId: operationPlanId
                });
                
                // Use the optimized single-update method that queries by matching fields
                const saveResult = await updateSinglePlantProgram({ 
                    plantId: plantId,
                    authSector: authSector,
                    productType: productType,
                    programCode: programCode,
                    shop: shop,
                    programIndex: programIndex,
                    operationPlanId: operationPlanId
                });
                
                if (saveResult.success) {
                    // Return the plantProgramId from the result (it should be in saveResult.programIds[0])
                    const updatedPlantProgramId = (saveResult.programIds && saveResult.programIds.length > 0) 
                        ? saveResult.programIds[0] 
                        : program.plantProgramId;
                    
                    // Refresh the data to get updated plantProgramIds (but don't wait for it)
                    this.dispatchEvent(new RefreshEvent());
                    
                    return { 
                        success: true, 
                        plantProgramId: updatedPlantProgramId 
                    };
                } else {
                    return { 
                        success: false, 
                        errorMessage: saveResult.message || 'Failed to update Plant Program' 
                    };
                }
            }

            // Fallback to full save process if Plant Program doesn't exist yet or other changes are needed
            // 0. Handle special shop combinations that need expansion
            const expandedShopResult = await this.handleSpecialShopCombinations();
            const expandedShopDataMap = expandedShopResult.expandedShopDataMap || {};
            const expandedInsertResult = expandedShopResult.insertResult || { shopMasterIdToPlantShopIdMap: {} };

            // 1. Prepare and insert new Plant Shops if needed (excluding expanded shops which are already inserted)
            const shopDataList = this.prepareShopDataList(expandedShopDataMap);
            const insertResult = await this.insertPlantShopsIfNeeded(shopDataList);
            
            // Merge expanded shop mappings into insertResult
            if (expandedInsertResult.shopMasterIdToPlantShopIdMap) {
                insertResult.shopMasterIdToPlantShopIdMap = insertResult.shopMasterIdToPlantShopIdMap || {};
                Object.assign(insertResult.shopMasterIdToPlantShopIdMap, expandedInsertResult.shopMasterIdToPlantShopIdMap);
            }

            // 2. Prepare Program Data List for Saving (with expanded shops)
            const programDataList = await this.prepareProgramDataList(insertResult, expandedShopDataMap);
            
            if (!programDataList || programDataList.length === 0) {
                return { success: false, errorMessage: 'No changes detected to save' };
            }

            // 3. Save Programs
            const saveResult = await savePrograms({ programDataListString: JSON.stringify(programDataList) });

            // 4. Create Plant Functions for new programs
            await this.handleCreatePlantFunctions(saveResult);
            
            // 5. Propagate Operation Plan changes for special shop combinations
            await this.propagateOperationPlanForSpecialShops();

            // Refresh the data to get updated plantProgramIds
            this.dispatchEvent(new RefreshEvent());
            
            // Find the newly created/updated plantProgramId from saveResult
            // The saveResult.programIds contains IDs of newly inserted programs (in order of programDataList)
            let newPlantProgramId = null;
            
            // First, check if the program already had a plantProgramId (it was updated, not inserted)
            if (shopMasterId && programValue) {
                const row = this.plantShopRows.find(r => r.key === shopMasterId);
                if (row) {
                    const program = row.programLoop.find(p => p.programValue === programValue);
                    if (program && program.plantProgramId) {
                        // Program already exists, use existing ID
                        newPlantProgramId = program.plantProgramId;
                    }
                }
            }
            
            // If not found and we have new program IDs, try to match by position in programDataList
            if (!newPlantProgramId && saveResult.programIds && saveResult.programIds.length > 0 && shopMasterId && programValue) {
                // Find the index of the program in programDataList that matches shopMasterId and programValue
                let matchingIndex = -1;
                for (let i = 0; i < programDataList.length; i++) {
                    const programData = programDataList[i];
                    // Match by programValue
                    if (programData.programValue === programValue) {
                        // Verify this program belongs to the correct shopMasterId by checking the row
                        const programRow = this.plantShopRows.find(r => {
                            return r.key === shopMasterId && r.programLoop.some(p => p.programValue === programValue);
                        });
                        if (programRow) {
                            matchingIndex = i;
                            break;
                        }
                    }
                }
                
                // If we found a match and the index is within programIds array, use that ID
                if (matchingIndex >= 0 && matchingIndex < saveResult.programIds.length) {
                    newPlantProgramId = saveResult.programIds[matchingIndex];
                } else if (saveResult.programIds.length === 1 && programDataList.length === 1) {
                    // If only one program was saved and only one in the list, use that ID
                    newPlantProgramId = saveResult.programIds[0];
                }
            }
            
            // If still not found, reload initial data to get updated IDs
            if (!newPlantProgramId && shopMasterId && programValue) {
                console.log('PlantProgramId not found in saveResult, reloading initial data...');
                try {
                    await this.loadInitialData();
                    // Try to find it again after reload
                    const updatedRow = this.plantShopRows.find(r => r.key === shopMasterId);
                    if (updatedRow) {
                        const updatedProgram = updatedRow.programLoop.find(p => p.programValue === programValue);
                        if (updatedProgram && updatedProgram.plantProgramId) {
                            newPlantProgramId = updatedProgram.plantProgramId;
                        }
                    }
                } catch (reloadError) {
                    console.error('Error reloading initial data:', reloadError);
                }
            }

            return { 
                success: true, 
                plantProgramId: newPlantProgramId,
                saveResult: saveResult
            };

        } catch (error) {
            console.error('===== SAVE FOR ALLOCATE ERROR =====');
            console.error('Error object:', error);
            console.error('Error message:', error?.body?.message || error?.message);
            console.error('Error body:', error?.body);
            console.error('Full error:', JSON.stringify(error, null, 2));
            
            const errorMessage = error?.body?.message || error?.message || 'An error occurred during save';
            return { success: false, errorMessage: errorMessage };
        } finally {
            console.log('Save for Allocate Finished. Setting isLoading to false');
            this.isLoading = false;
        }
    }

    /**
     * Check if a shop combination requires expansion to multiple shops
     * @param {String} authSector - Sector value
     * @param {String} productType - Product Type value
     * @param {String} shop - Shop value
     * @returns {Object|null} - Returns exclusion criteria if expansion needed, null otherwise
     */
    shouldExpandShop(authSector, productType, shop) {
        const shopNorm = (shop || '').trim();
        // Assembly-Vehicle-"All Except Body, Paint" → exclude "All Except Body, Paint", "Body", "Paint"
        if (authSector === 'Assembly' && productType === 'Vehicle' && isShopAllExceptBodyPaint(shopNorm)) {
            return { excludeShops: [SHOP_ALL_EXCEPT_BODY_PAINT, 'Body', 'Paint'] };
        }
        
        // GPS/Polymers/Press-"All" → exclude "All"
        if (isShopAll(shopNorm)) {
            if ((authSector === 'GPS' && ['Battery', 'Drive Unit', 'Engine', 'Transmission'].includes(productType)) ||
                (authSector === 'Polymers' && productType === 'Polymers') ||
                (authSector === 'Press' && productType === 'Press')) {
                return { excludeShops: [SHOP_ALL] };
            }
        }
        
        return null;
    }

    /**
     * Check if a row is expandable (i.e., it's a special shop combination with child programs)
     * @param {Object} row - The plant shop row
     * @returns {Boolean} True if the row can be expanded
     */
    isRowExpandable(row) {
        const expansionCriteria = this.shouldExpandShop(row.authSector, row.productType, row.shop);
        return expansionCriteria !== null;
    }

    /**
     * Check if a row is currently expanded
     * @param {String} key - The row key
     * @returns {Boolean} True if the row is expanded
     */
    isRowExpanded(key) {
        return this.expandedRows.has(key);
    }

    /**
     * Handle click on expand/collapse icon
     * @param {Event} event - The click event
     */
    async handleToggleExpand(event) {
        const rowKey = event.currentTarget.dataset.key;
        const row = this.plantShopRows.find(r => r.key === rowKey);
        
        if (!row) {
            console.error('Row not found for key:', rowKey);
            return;
        }

        // Toggle expanded state
        if (this.expandedRows.has(rowKey)) {
            // Collapse
            this.expandedRows.delete(rowKey);
            // Force reactivity
            this.expandedRows = new Set(this.expandedRows);
            this.updateRowExpandState(rowKey, false);
        } else {
            // Expand - load child programs if not already loaded
            if (!this.childProgramsMap[rowKey]) {
                await this.loadChildPrograms(row);
            }
            this.expandedRows.add(rowKey);
            // Force reactivity
            this.expandedRows = new Set(this.expandedRows);
            this.updateRowExpandState(rowKey, true);
        }
    }

    /**
     * Update row's isExpanded property for reactivity
     * @param {String} rowKey - The row key
     * @param {Boolean} isExpanded - Whether the row is expanded
     */
    updateRowExpandState(rowKey, isExpanded) {
        this.plantShopRows = this.plantShopRows.map(row => {
            if (row.key === rowKey) {
                return { ...row, isExpanded };
            }
            return row;
        });
    }

    /**
     * Load child Plant Programs for an expandable row
     * @param {Object} row - The plant shop row
     */
    async loadChildPrograms(row) {
        const expansionCriteria = this.shouldExpandShop(row.authSector, row.productType, row.shop);
        
        if (!expansionCriteria) {
            console.error('Row is not expandable:', row);
            return;
        }

        try {
            this.isLoading = true;
            
            let childPrograms = await getChildPlantPrograms({
                plantId: this.recordId,
                sector: row.authSector,
                productType: row.productType,
                excludeShops: expansionCriteria.excludeShops
            });

            // Fallback: when no Plant_Shop__c/Plant_Program__c exist yet, show child Shop_Master__c
            // so the user sees available shops they can configure (accordion structure)
            if (!childPrograms || childPrograms.length === 0) {
                const childShopMasters = await getShopMastersByCriteria({
                    sector: row.authSector,
                    productType: row.productType,
                    excludeShops: expansionCriteria.excludeShops
                });
                childPrograms = childShopMasters.map(sm => ({
                    shop: sm.Shop__c,
                    shopMasterId: sm.Id,
                    plantShopId: null,
                    sector: row.authSector,
                    productType: row.productType,
                    programIndex: 'A',
                    plantProgramId: null,
                    programCode: '',
                    programName: '',
                    isIncluded: false,
                    operationPlanId: null
                }));
            }

            console.log('Loaded child programs for row:', row.key, childPrograms);

            // Group child programs by shop for display
            const programsByShop = {};
            childPrograms.forEach(prog => {
                if (!programsByShop[prog.shop]) {
                    programsByShop[prog.shop] = {
                        shop: prog.shop,
                        shopMasterId: prog.shopMasterId,
                        plantShopId: prog.plantShopId,
                        sector: prog.sector,
                        productType: prog.productType,
                        programs: {}
                    };
                }
                // Store program by index (A, B, C, etc.)
                programsByShop[prog.shop].programs[prog.programIndex] = {
                    plantProgramId: prog.plantProgramId,
                    programIndex: prog.programIndex,
                    programCode: prog.programCode,
                    programName: prog.programName,
                    isIncluded: prog.isIncluded,
                    operationPlanId: prog.operationPlanId
                };
            });

            // Convert to array and create programList for each shop
            const childRows = Object.values(programsByShop)
                .sort((a, b) => a.shop.localeCompare(b.shop))
                .map(shopData => ({
                    ...shopData,
                    // Create programList array for template iteration
                    programList: this.programValues.map(progValue => {
                        const prog = shopData.programs[progValue];
                        const opPlanId = prog?.operationPlanId ? String(prog.operationPlanId) : '';
                        const parentProg = (row.programLoop || []).find(p => p.programValue === progValue);
                        const isParentSelected = parentProg ? parentProg.isSelected !== false : true;
                        const actualProgramCode = prog?.programCode || '';
                        const actualOperationPlanId = opPlanId;
                        return {
                            programIndex: progValue,
                            hasProgram: !!prog,
                            plantProgramId: prog?.plantProgramId || null,
                            programCode: isParentSelected ? actualProgramCode : '',
                            programName: prog?.programName || '',
                            isIncluded: prog?.isIncluded || false,
                            operationPlanId: isParentSelected ? actualOperationPlanId : '',
                            isOpPlanReadOnly: isParentSelected ? !!opPlanId : false
                        };
                    })
                }));

            // Store in map
            this.childProgramsMap = {
                ...this.childProgramsMap,
                [row.key]: childRows
            };

            // Update the row with childRows for template reactivity
            this.plantShopRows = this.plantShopRows.map(r => {
                if (r.key === row.key) {
                    return { ...r, childRows };
                }
                return r;
            });

            console.log('Child programs loaded:', childRows);

        } catch (error) {
            console.error('Error loading child programs:', error);
            this.showToast('Error', 'Failed to load child programs: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle click on Allocate button for a child program
     * @param {Event} event - The click event
     */
    async handleChildAllocateClick(event) {
        const plantProgramId = event.currentTarget.dataset.plantProgramId;
        const shop = event.currentTarget.dataset.shop;
        
        if (!plantProgramId) {
            this.showToast('Error', 'Plant Program ID is missing.', 'error');
            return;
        }

        console.log('Allocate clicked for child program:', plantProgramId, 'Shop:', shop);

        // Navigate to manageShiftsSetup for user to configure shift change options
        const pageReference = {
            type: 'standard__component',
            attributes: {
                componentName: 'c__manageShiftsSetup'
            },
            state: {
                c__plantProgramId: plantProgramId,
                c__plantName: encodeURIComponent(this.plantName || '')
            }
        };

        // Open in new subtab
        this[NavigationMixin.Navigate](pageReference, false);
    }

    /**
     * Handle Op Plan Default change for a child program
     */
    async handleChildOperationPlanChange(event) {
        const plantProgramId = event.currentTarget.dataset.plantProgramId;
        const newOperationPlanId = event.detail.value || '';
        const parentKey = event.currentTarget.dataset.parentKey;

        if (!plantProgramId) {
            this.showToast('Error', 
                'Plant Program not found for this row. Collapse the accordion, then expand it again to refresh after Save. Or set Op Plan on the parent row (All / All Except Body, Paint) and Save to propagate to all child shops.', 
                'error');
            return;
        }

        try {
            const result = await updatePlantProgramOpPlan({ plantProgramId, operationPlanId: newOperationPlanId });
            if (result.success) {
                this.showToast('Success', result.message || 'Op Plan updated', 'success');
                // Update the child row's operationPlanId and isOpPlanReadOnly in local state
                const row = this.plantShopRows.find(r => r.key === parentKey);
                if (row && row.childRows) {
                    row.childRows.forEach(childRow => {
                        const prog = childRow.programList.find(p => p.plantProgramId === plantProgramId);
                        if (prog) {
                            prog.operationPlanId = newOperationPlanId;
                            prog.isOpPlanReadOnly = !!newOperationPlanId;
                        }
                    });
                    this.plantShopRows = [...this.plantShopRows];
                }
            } else {
                this.showToast('Error', result.message || 'Failed to update Op Plan', 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to update Op Plan: ' + (error.body?.message || error.message), 'error');
        }
    }

    /**
     * Handle special shop combinations that need to be expanded to multiple shops
     * @returns {Object} Object containing expandedShopDataMap and insertResult
     */
    async handleSpecialShopCombinations() {
        const expandedShopDataMap = {};
        const shopDataListToInsert = [];
        
        // Check each row for special shop combinations
        for (const plantShopRow of this.plantShopRows || []) {
            const expansionCriteria = this.shouldExpandShop(
                plantShopRow.authSector,
                plantShopRow.productType,
                plantShopRow.shop
            );
            
            if (expansionCriteria) {
                console.log('Found special shop combination:', {
                    sector: plantShopRow.authSector,
                    productType: plantShopRow.productType,
                    shop: plantShopRow.shop,
                    excludeShops: expansionCriteria.excludeShops
                });
                
                // Check if any NEW programs need to be created for this row.
                // Only trigger expansion for programs that don't yet exist (no plantProgramId).
                // Updates to existing programs are handled by propagateProgramCodeAndNameForSpecialShops
                // and propagateOperationPlanForSpecialShops - no need to re-expand.
                const hasProgramsToSave = plantShopRow.programLoop.some(program => 
                    program.isVisible && !program.plantProgramId && program.isSelected
                );
                
                if (hasProgramsToSave) {
                    // Query for matching shop masters
                    try {
                        const matchingShops = await getShopMastersByCriteria({
                            sector: plantShopRow.authSector,
                            productType: plantShopRow.productType,
                            excludeShops: expansionCriteria.excludeShops
                        });
                        
                        console.log(`Found ${matchingShops.length} matching shops for expansion`);
                        
                        // Add to shop data list for insertion
                        matchingShops.forEach(shopMaster => {
                            shopDataListToInsert.push({
                                plantId: this.recordId,
                                shopMasterId: shopMaster.Id
                            });
                        });
                        
                        // Store mapping for later use in prepareProgramDataList
                        matchingShops.forEach(shopMaster => {
                            // Only cascade programs that are NEW (no existing record) and selected.
                            // If user checks A on parent, only A cascades; existing B is not re-created.
                            const expandedProgramLoop = plantShopRow.programLoop
                                .filter(prog => prog.isSelected && !prog.plantProgramId)
                                .map(prog => ({
                                    ...prog,
                                    plantProgramId: null,
                                    isChanged: prog.isChanged || false
                                }));
                            
                            expandedShopDataMap[shopMaster.Id] = {
                                shopMasterId: shopMaster.Id,
                                authSector: shopMaster.Auth_Sector__c,
                                productType: shopMaster.Product_Type__c,
                                shop: shopMaster.Shop__c,
                                programLoop: expandedProgramLoop // Use program loop with cleared plantProgramId
                            };
                        });
                    } catch (error) {
                        console.error('Error querying shop masters for expansion:', error);
                        throw error;
                    }
                }
            }
        }
        
        // Insert Plant Shops for expanded shops
        let insertResult = { shopMasterIdToPlantShopIdMap: {} };
        if (shopDataListToInsert.length > 0) {
            console.log(`Inserting ${shopDataListToInsert.length} Plant Shops for expanded shops`);
            insertResult = await this.insertPlantShopsIfNeeded(shopDataListToInsert);
            
            // Map shop master IDs to plant shop IDs
            if (insertResult && insertResult.shopMasterIdToPlantShopIdMap) {
                Object.keys(expandedShopDataMap).forEach(shopMasterId => {
                    const plantShopId = insertResult.shopMasterIdToPlantShopIdMap[shopMasterId];
                    if (plantShopId) {
                        expandedShopDataMap[shopMasterId].plantShopId = plantShopId;
                    }
                });
            }
        }
        
        return {
            expandedShopDataMap: expandedShopDataMap,
            insertResult: insertResult
        };
    }

    prepareShopDataList(expandedShopDataMap = {}) {
        const shopDataList = [];
        if (!this.recordId) {
            console.error('⚠️ prepareShopDataList: recordId is not set!');
            return shopDataList;
        }
        (this.plantShopRows || []).forEach(plantShopRow => {
            // Note: Master rows (All, All Except Body, Paint) now ALSO get Plant_Shop__c created
            // so that Plant Programs can be created to store Op Plan Default values
            // Individual shops are still created via expansion logic
            
            // Only insert Plant Shop if:
            // 1. plantShopId is null (not yet created)
            // 2. shopMasterId is not null (has a valid Shop Master)
            // 3. Not a custom row (custom rows don't need Plant_Shop__c records)
            if (plantShopRow.plantShopId === null && 
                plantShopRow.shopMasterId !== null && 
                !plantShopRow.isCustomRow) {
                shopDataList.push({
                    plantId: this.recordId,
                    shopMasterId: plantShopRow.shopMasterId
                });
            }
        });
        return shopDataList;
    }
    
    /**
     * Propagate Operation Plan changes for special shop combinations
     * When Op Plan is changed on "All Except Body, Paint" or "All" rows,
     * update Shifts_Def__c on ALL matching Plant_Program__c records including
     * those with Shop = "All" and "All Except Body, Paint".
     */
    async propagateOperationPlanForSpecialShops() {
        const propagationPromises = [];
        
        for (const plantShopRow of this.plantShopRows || []) {
            const expansionCriteria = this.shouldExpandShop(
                plantShopRow.authSector,
                plantShopRow.productType,
                plantShopRow.shop
            );
            
            if (expansionCriteria) {
                // Check each program in the row for operation plan changes
                for (const program of plantShopRow.programLoop || []) {
                    // Propagate when program has a changed operation plan and is selected
                    if (program.isVisible && program.isChanged && program.operationPlanId) {
                        propagationPromises.push(
                            propagateOperationPlanToMatchingPrograms({
                                plantId: this.recordId,
                                sector: plantShopRow.authSector,
                                productType: plantShopRow.productType,
                                excludeShops: [], // Empty = update ALL matching programs including All, All Except Body, Paint
                                operationPlanId: program.operationPlanId,
                                programIndex: program.programValue
                            }).catch(error => {
                                console.error('Error propagating operation plan:', error);
                                throw error;
                            })
                        );
                    }
                }
            }
        }
        
        if (propagationPromises.length > 0) {
            await Promise.all(propagationPromises);
        }
    }

    /**
     * When checkbox is unchecked on a master row (All or All Except Body, Paint),
     * set Include__c = false on ALL matching Plant_Program__c records (master + child shops).
     * Always uses setIncludeFalseForMatchingPrograms so the uncheck cascades per program index.
     */
    async propagateIncludeFalseForMasterRows() {
        const propagationPromises = [];
        const plantId = this.recordId;

        if (!plantId) {
            console.warn('propagateIncludeFalseForMasterRows: recordId/plantId not set');
            return;
        }

        for (const plantShopRow of this.plantShopRows || []) {
            const shopNorm = (plantShopRow.shop || '').trim();
            if (!isShopAll(shopNorm) && !isShopAllExceptBodyPaint(shopNorm)) {
                continue;
            }

            for (const program of plantShopRow.programLoop || []) {
                if (program.isVisible && !program.isSelected && (program.isChanged || program.plantProgramId)) {
                    // Always use setIncludeFalseForMatchingPrograms so uncheck cascades to ALL matching
                    // records (master row + child shops under the accordion) per program index
                    propagationPromises.push(
                        setIncludeFalseForMatchingPrograms({
                            plantId: plantId,
                            sector: plantShopRow.authSector,
                            productType: plantShopRow.productType,
                            programIndex: program.programValue
                        }).catch(error => {
                            console.error('Error propagating Include__c=false:', error);
                            throw error;
                        })
                    );
                }
            }
        }

        if (propagationPromises.length > 0) {
            await Promise.all(propagationPromises);
        }
    }

    /**
     * When checkbox is checked again on a master row (All or All Except Body, Paint),
     * set Include__c = true on ALL matching Plant_Program__c records (master + child shops).
     * Mirrors propagateIncludeFalseForMasterRows for the re-check scenario.
     */
    async propagateIncludeTrueForMasterRows() {
        const propagationPromises = [];
        const plantId = this.recordId;

        if (!plantId) {
            console.warn('propagateIncludeTrueForMasterRows: recordId/plantId not set');
            return;
        }

        for (const plantShopRow of this.plantShopRows || []) {
            const shopNorm = (plantShopRow.shop || '').trim();
            if (!isShopAll(shopNorm) && !isShopAllExceptBodyPaint(shopNorm)) {
                continue;
            }

            for (const program of plantShopRow.programLoop || []) {
                if (program.isVisible && program.isSelected && program.isIncludeChanged) {
                    propagationPromises.push(
                        setIncludeTrueForMatchingPrograms({
                            plantId: plantId,
                            sector: plantShopRow.authSector,
                            productType: plantShopRow.productType,
                            programIndex: program.programValue
                        }).catch(error => {
                            console.error('Error propagating Include__c=true:', error);
                            throw error;
                        })
                    );
                }
            }
        }

        if (propagationPromises.length > 0) {
            await Promise.all(propagationPromises);
        }
    }

    /**
     * Propagate Program Code and Program Name changes for special shop combinations
     * When Program Code/Name is changed on "All Except Body, Paint" or "All" rows,
     * cascade to all Plant_Program__c records whose shop comes under that accordion
     */
    async propagateProgramCodeAndNameForSpecialShops() {
        const propagationPromises = [];
        
        for (const plantShopRow of this.plantShopRows || []) {
            const expansionCriteria = this.shouldExpandShop(
                plantShopRow.authSector,
                plantShopRow.productType,
                plantShopRow.shop
            );
            
            if (expansionCriteria) {
                for (const program of plantShopRow.programLoop || []) {
                    const programCode = program.selectedProgramCode || program.programCode || '';
                    const programName = program.plantProgramName || program.programName || '';
                    const hasProgramCodeOrName = (programCode && programCode.trim() !== '') || (programName && programName.trim() !== '');
                    
                    if (program.isVisible && program.isSelected && program.isProgramDetailChanged && hasProgramCodeOrName) {
                        propagationPromises.push(
                            propagateProgramCodeAndNameToMatchingPrograms({
                                plantId: this.recordId,
                                sector: plantShopRow.authSector,
                                productType: plantShopRow.productType,
                                excludeShops: expansionCriteria.excludeShops,
                                programCode: programCode.trim() || null,
                                programName: programName.trim() || null,
                                programIndex: program.programValue
                            }).catch(error => {
                                console.error('Error propagating Program Code/Name:', error);
                                throw error;
                            })
                        );
                    }
                }
            }
        }
        
        if (propagationPromises.length > 0) {
            await Promise.all(propagationPromises);
        }
    }

    async prepareProgramDataList(insertResult, expandedShopDataMap = {}) {
        let programDataList = [];
        
        // Gate for NEW Program Index B creation only (does not affect updates to existing records)
        const shouldCreateProgramIndexB = (program, authSector, productType, shop) => {
            if (program.programValue !== 'B') {
                return true;
            }
            
            // For GPS-Engine-All: only create if programCode is "Gen V" or "GenV"
            if (authSector === 'GPS' && productType === 'Engine' && isShopAll(shop)) {
                const programCode = (program.selectedProgramCode || program.programCode || '').trim();
                return programCode === 'Gen V' || programCode === 'GenV';
            }
            
            return true;
        };
        
        // Helper to get programCode/programName for save - GPS-Engine Program B must use 'Gen V'
        const getProgramCodeForSave = (program, authSector, productType, shop) => {
            const code = (program.selectedProgramCode || program.programCode || '').trim();
            // if (authSector === 'GPS' && productType === 'Engine' && isShopAll(shop) && program.programValue === 'B') {
            //     return (code === 'Gen V' || code === 'GenV') ? 'Gen V' : code;
            // }
            return code;
        };
        const getProgramNameForSave = (program, authSector, productType, shop) => {
            const name = (program.plantProgramName || program.programName || '').trim();
            // if (authSector === 'GPS' && productType === 'Engine' && isShopAll(shop) && program.programValue === 'B') {
            //     const code = getProgramCodeForSave(program, authSector, productType, shop);
            //     return (code === 'Gen V') ? 'Gen V' : (name || code);
            // }
            return name;
        };

        // Helper function to add program data to the list
        const addProgramData = (program, plantShopId, shopMasterId, authSector, productType, shop) => {
            if (!program.isVisible) return;

            const programCodeForSave = getProgramCodeForSave(program, authSector, productType, shop);
            const programNameForSave = getProgramNameForSave(program, authSector, productType, shop);

            if (!program.plantProgramId && program.isSelected) {
                // INSERT new — apply Program Index B creation gate
                if (!shouldCreateProgramIndexB(program, authSector, productType, shop)) {
                    return;
                }
                programDataList.push({
                    plantProgramId: null,
                    plantId: this.recordId,
                    plantShopId: plantShopId,
                    programValue: program.programValue,
                    programCode: programCodeForSave,
                    programName: programNameForSave || programCodeForSave,
                    isSelected: program.isSelected,
                    operationPlanId: program.operationPlanId,
                    auth3rdShiftValue: program.auth3rdShiftValue || null,
                    functionShiftValues: program.functionShiftValues || null,
                    functionShift2ndValues: program.functionShift2ndValues || null,
                    workbookShiftValues: program.workbookShiftValues || null,
                    workbookShift2ndValues: program.workbookShift2ndValues || null
                });
            } else if (program.plantProgramId && program.isSelected) {
                // UPDATE existing selected — always include to persist changes
                programDataList.push({
                    plantProgramId: program.plantProgramId,
                    plantId: this.recordId,
                    plantShopId: plantShopId,
                    programValue: program.programValue,
                    programCode: programCodeForSave,
                    programName: programNameForSave || programCodeForSave,
                    isSelected: program.isSelected,
                    operationPlanId: program.operationPlanId,
                    auth3rdShiftValue: program.auth3rdShiftValue || null,
                    functionShiftValues: program.functionShiftValues || null,
                    functionShift2ndValues: program.functionShift2ndValues || null,
                    workbookShiftValues: program.workbookShiftValues || null,
                    workbookShift2ndValues: program.workbookShift2ndValues || null
                });
            } else if (program.plantProgramId && !program.isSelected) {
                // UPDATE existing unchecked — persist Include__c = false
                programDataList.push({
                    plantProgramId: program.plantProgramId,
                    plantId: this.recordId,
                    plantShopId: plantShopId,
                    programValue: program.programValue,
                    programCode: programCodeForSave,
                    programName: programNameForSave || programCodeForSave,
                    isSelected: false,
                    operationPlanId: program.operationPlanId,
                    auth3rdShiftValue: program.auth3rdShiftValue || null,
                    functionShiftValues: program.functionShiftValues || null,
                    functionShift2ndValues: program.functionShift2ndValues || null,
                    workbookShiftValues: program.workbookShiftValues || null,
                    workbookShift2ndValues: program.workbookShift2ndValues || null
                });
            }
        };
        
        // Process all rows (including master rows like "All", "All Except Body, Paint")
        // Master rows now get Plant Programs created so Op Plan Default values can be stored
        this.plantShopRows.forEach(plantShopRow => {
            let plantShopId = plantShopRow.plantShopId;
            
            // Skip custom rows that don't have a plantShopId and aren't being saved
            if (plantShopRow.isCustomRow && !plantShopId) {
                return;
            }
            
            // Note: Master rows (All, All Except Body, Paint) now ALSO get Plant Programs created
            // so that Op Plan Default values can be stored and displayed
            // Individual shops are still created via expansion logic below
            
            if (!plantShopId) {
                plantShopId = insertResult.shopMasterIdToPlantShopIdMap?.[plantShopRow.shopMasterId];
            }

            plantShopRow.programLoop.forEach(program => {
                addProgramData(program, plantShopId, plantShopRow.shopMasterId, plantShopRow.authSector, plantShopRow.productType, plantShopRow.shop);
            });
        });
        
        // Process expanded shops
        Object.keys(expandedShopDataMap).forEach(shopMasterId => {
            const expandedShop = expandedShopDataMap[shopMasterId];
            const plantShopId = expandedShop.plantShopId || insertResult.shopMasterIdToPlantShopIdMap?.[shopMasterId];
            
            if (!plantShopId) {
                return;
            }
            
            // Get sector, productType, and shop from expandedShop
            const authSector = expandedShop.sector || expandedShop.authSector || '';
            const productType = expandedShop.productType || '';
            const shop = expandedShop.shop || '';
            
            // Process each program in the program loop
            expandedShop.programLoop.forEach(program => {
                addProgramData(program, plantShopId, shopMasterId, authSector, productType, shop);
            });
        });
        
        // Deduplicate by plantProgramId to prevent "Duplicate id in list" errors
        // If the same plantProgramId appears multiple times, keep the last occurrence (most recent changes)
        const seenIds = new Map();
        const deduplicatedList = [];
        
        // Process in reverse order so we keep the last occurrence of each ID
        for (let i = programDataList.length - 1; i >= 0; i--) {
            const programData = programDataList[i];
            const programId = programData.plantProgramId;
            
            // For updates (has plantProgramId), check for duplicates
            if (programId && programId !== null && programId !== '') {
                if (!seenIds.has(programId)) {
                    seenIds.set(programId, true);
                    deduplicatedList.unshift(programData); // Add to beginning to maintain order
                }
            } else {
                // For inserts (no plantProgramId), always include (no deduplication needed)
                deduplicatedList.unshift(programData);
            }
        }
        
        return deduplicatedList;
    }

    async handleCreatePlantFunctions(saveResult) {
        if (saveResult.success && saveResult.programIds && saveResult.programIds.length > 0) {
            const result = await createPlantFunctions({ plantProgramIds: saveResult.programIds });
            return result;
        } else {
            return { success: true, message: 'No plant programs to create functions for.' };
        }
    }


    /**
     * Inserts plant shops if shopDataList is provided and not empty.
     * Returns a promise resolving with the save result or a success message if nothing to insert.
     */
    async insertPlantShopsIfNeeded(shopDataList) {
        if (!Array.isArray(shopDataList) || shopDataList.length === 0) {
            return { success: true, message: 'No shops to insert.' };
        }

        try {
            const result = await savePlantShops({ shopDataListString: JSON.stringify(shopDataList) });
            return result;
        } catch (error) {
            console.error('Error inserting plant shops:', error.body?.message || error.message);
            throw error;
        }
    }

    handleDebug() {
        console.log('🐛 DEBUG DATA DUMP 🐛');
        console.log('plantShopRows:', JSON.parse(JSON.stringify(this.plantShopRows)));
        this.plantShopRows.forEach((row, index) => {
            console.log(`\n=== Row ${index}: ${row.authSector} > ${row.productType} > ${row.shop} ===`);
            row.programLoop.forEach(prog => {
                if (prog.isVisible) {
                    console.log(`  Program ${prog.programValue}:`, {
                        plantProgramId: prog.plantProgramId,
                        isSelected: prog.isSelected,
                        operationPlanId: prog.operationPlanId,
                        isChanged: prog.isChanged,
                        programCode: prog.programCode
                    });
                }
            });
        });
    }

    handleCancel() {
        this.handleCloseDeactivateProgramModal();
        this.pendingEquationReparentRequests = [];
        // If there are unsaved changes, restore original state
        if (this.hasUnsavedChanges && this.originalPlantShopRows.length > 0) {
            // Restore original state (deep clone to avoid mutation)
            this.plantShopRows = JSON.parse(JSON.stringify(this.originalPlantShopRows));
            this.hasUnsavedChanges = false;
            
            // Reload program codes after restoring state
            this.reloadProgramCodesAfterPlantNameLoad();
            
            this.showToast('Info', 'Changes have been reverted', 'info');
        } else {
            // No changes to undo, just close the modal
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    getMatchingProgramMasters(authSector, productType) {
        if (!this.programMasters || this.programMasters.length === 0) {
            return [];
        }

        const sector = authSector || '';
        const prodType = productType || '';

        return this.programMasters.filter(pm =>
            pm.Sector__c === sector &&
            pm.Product__c === prodType &&
            pm.Program_Code__c
        );
    }

    /**
     * Gets Program Code from Program_Master__c based on Auth Sector, Product Type, and Program Index
     * Only returns program codes for Program Index A (not B, C, D, E)
     * Special case: GPS-Engine Program Index B returns 'Gen V'
     */
    getProgramCodeFromMaster(authSector, productType, programValue) {
        const sector = authSector || '';
        const prodType = productType || '';
        const progIndex = programValue || '';
        
        // Only return program codes for Program Index A
        // Exception: GPS-Engine Program Index B returns 'Gen V'
        if (progIndex !== 'A' && !(sector === 'GPS' && prodType === 'Engine' && progIndex === 'B')) {
            return null;
        }
        
        // Special handling for GPS-Engine Program Index B
        if (sector === 'GPS' && prodType === 'Engine' && progIndex === 'B') {
            return 'Gen V';
        }
        
        // Find matching Program_Master__c records for Program Index A
        const matchingPrograms = this.getMatchingProgramMasters(sector, prodType);
        
        if (matchingPrograms.length > 0) {
            // For Program Index A, use Program_Code__c from Program_Master__c
            const programCode = matchingPrograms[0].Program_Code__c;
            if (programCode) {
                return programCode;
            }
        }
        
        return null;
    }
    
    /**
     * Gets Spring Hill specific Plant Program Name defaults
     */
    getSpringHillProgramName(authSector, productType, programCode, programValue) {
        const isSpringHill = this.plantName && this.plantName.toLowerCase().includes('spring hill');
        if (!isSpringHill) {
            return '';
        }
        
        const sector = authSector || '';
        const prodType = productType || '';
        const progCode = programCode || '';
        const progIndex = programValue || '';
        
        // Spring Hill specific defaults
        if (sector === 'Assembly' && prodType === 'Vehicle') {
            return 'Mid Size SUV';
        } else if (sector === 'GPS' && prodType === 'Battery' && progCode === 'Ultium') {
            return 'Ultium';
        } else if (sector === 'GPS' && prodType === 'Engine' && progCode === 'CSS') {
            return 'CSS';
        } else if (sector === 'GPS' && prodType === 'Engine' && progCode === 'Gen V') {
            return 'Gen V';
        }
        
        return '';
    }
    
    /**
     * Determines Program Code and Program Name based on Auth Sector, Product Type, Shop, and Program Index
     * Now uses Program_Master__c for initial rendering
     * For Spring Hill: Shows program code/name by default with specific Plant Program Name defaults
     * For other plants: Shows dropdown to select program (like GPS - Drive Unit)
     */
    getProgramInfo(authSector, productType, shop, programValue) {
        let programCode = '';
        let programName = '';
        let showDropdown = false;

        // Normalize values for comparison
        const sector = authSector || '';
        const prodType = productType || '';
        const shopValue = shop || '';
        const progIndex = programValue || '';
        
        // Check if plant is Spring Hill
        const isSpringHill = this.plantName && this.plantName.toLowerCase().includes('spring hill');
        
        // Try to get program code from Program_Master__c first
        // Only for Program Index A (or GPS-Engine Program Index B)
        const masterProgramCode = this.getProgramCodeFromMaster(sector, prodType, progIndex);
        if (masterProgramCode) {
            programCode = masterProgramCode;
            // Get Spring Hill specific program name if applicable (only for Program Index A)
            if (progIndex === 'A' || (sector === 'GPS' && prodType === 'Engine' && progIndex === 'B')) {
                programName = this.getSpringHillProgramName(sector, prodType, programCode, progIndex);
            }
            
            // For Program Index A, show the code (no dropdown)
            // For GPS-Engine Program Index B, show the code (no dropdown)
            if (progIndex === 'A' || (sector === 'GPS' && prodType === 'Engine' && progIndex === 'B')) {
                showDropdown = false;
            } else {
                // For Program Index B+ (except GPS-Engine B), show dropdown
                showDropdown = true;
            }
        } else {
            // No program code from Program_Master__c - show dropdown for Program Index B+
            if (progIndex !== 'A') {
                showDropdown = true;
            }
        }
        
        // Apply program code rules based on sector/product type/shop regardless of plant name
        // These rules apply to all plants, not just Spring Hill
        // Only apply if we didn't get program code from Program_Master__c
        
        if (!programCode) {
            // Fallback to existing hardcoded rules if Program_Master__c doesn't have the data
            // Only set defaults for Program Index A (not B+)
            // Exception: GPS-Engine Program Index B gets 'Gen V'
            
            // Assembly Sector Rules - only Program Index A
            if (sector === 'Assembly' && progIndex === 'A') {
                if (isShopAllExceptBodyPaint(shopValue)) {
                    programCode = 'Mid Size SUV';
                    programName = ''; // Hide program name
                } else if (shopValue === 'Body') {
                    programCode = 'Mid Size SUV';
                    programName = ''; // Hide program name
                } else if (shopValue === 'Paint') {
                    programCode = 'Mid Size SUV';
                    programName = 'Mid Size SUV';
                }
            } else if (sector === 'Assembly' && progIndex !== 'A') {
                // For Program Index B+, show dropdown
                showDropdown = true;
            }
            // GPS Sector Rules - only Program Index A and GPS-Engine Program Index B
            else if (sector === 'GPS') {
                if (prodType === 'Engine') {
                    if (progIndex === 'A') {
                        programCode = 'CSS';
                        programName = ''; // Hide program name
                    } else if (progIndex === 'B') {
                        // GPS-Engine Program Index B gets 'Gen V'
                        programCode = 'Gen V';
                        programName = ''; // Hide program name
                        showDropdown = false;
                    } else {
                        // Program Index C+ shows dropdown
                        showDropdown = true;
                    }
                } else if (prodType === 'Battery' && progIndex === 'A') {
                    programCode = 'Ultium';
                    programName = ''; // Hide program name
                } else if (prodType === 'Battery' && progIndex !== 'A') {
                    // Battery Program Index B+ shows dropdown
                    showDropdown = true;
                }
            }
            // Press Sector - only Program Index A
            else if (sector === 'Press' && progIndex === 'A') {
                programCode = 'Press';
                programName = ''; // Hide program name
            } else if (sector === 'Press' && progIndex !== 'A') {
                showDropdown = true;
            }
            // Polymers Sector - only Program Index A
            else if (sector === 'Polymers' && progIndex === 'A') {
                programCode = 'Polymers';
                programName = ''; // Hide program name
            } else if (sector === 'Polymers' && progIndex !== 'A') {
                showDropdown = true;
            }
            
            // For non-Spring Hill plants, if no program code was determined by rules, show dropdown
            if (!isSpringHill && !programCode && !showDropdown) {
                showDropdown = true;
            }
        }

        return { programCode, programName, showDropdown };
    }
    
    /**
     * Gets shops from Shop_Master__c based on Auth_Sector__c and Product_Type__c from Program_Master__c
     * Groups shops appropriately:
     * - Body and Paint shops standalone (no accordion)
     * - Other Assembly-Vehicle shops in "All Except Body, Paint" accordion
     * - Other sector shops in "All" accordion
     */
    getShopsForSectorProductType(authSector, productType) {
        if (!this.shopMasters || this.shopMasters.length === 0) {
            return [];
        }
        
        const sector = authSector || '';
        const prodType = productType || '';
        
        // Filter shops matching the sector and product type
        const matchingShops = this.shopMasters.filter(sm => 
            sm.Auth_Sector__c === sector && sm.Product_Type__c === prodType
        );
        
        return matchingShops;
    }
    
    /**
     * Groups shops for initial rendering:
     * - Body and Paint shops standalone (no accordion)
     * - Other Assembly-Vehicle shops in "All Except Body, Paint" accordion
     * - Other sector shops in "All" accordion
     */
    groupShopsForRendering(shops, authSector, productType) {
        const sector = authSector || '';
        const prodType = productType || '';
        
        const bodyShop = shops.find(s => (s.Shop__c || '').trim() === 'Body');
        const paintShop = shops.find(s => (s.Shop__c || '').trim() === 'Paint');
        const allShop = shops.find(s => isShopAll(s.Shop__c));
        const allExceptBodyPaintShop = shops.find(s => isShopAllExceptBodyPaint(s.Shop__c));
        const otherShops = shops.filter(s => {
            const shop = (s.Shop__c || '').trim();
            return shop !== 'Body' && shop !== 'Paint' && !isShopAll(shop) && !isShopAllExceptBodyPaint(shop);
        });
        
        const result = [];
        
        // For Assembly-Vehicle: Body and Paint standalone, others in "All Except Body, Paint"
        if (sector === 'Assembly' && prodType === 'Vehicle') {
            // Add Body shop standalone
            if (bodyShop) {
                result.push(bodyShop);
            }
            // Add Paint shop standalone
            if (paintShop) {
                result.push(paintShop);
            }
            // Add "All Except Body, Paint" shop if it exists (this is an accordion row)
            if (allExceptBodyPaintShop) {
                result.push(allExceptBodyPaintShop);
            } else if (otherShops.length > 0) {
                // If "All Except Body, Paint" doesn't exist but we have other shops,
                // we need to find or create it - for now, add other shops individually
                // This might need to be handled differently if Shop_Master__c doesn't have this shop
                result.push(...otherShops);
            }
        } else {
            // For other sectors: Use "All" shop if it exists, otherwise list individual shops
            if (allShop) {
                result.push(allShop);
            } else {
                // Add all shops (including Body/Paint if they exist for other sectors)
                result.push(...shops);
            }
        }
        
        return result;
    }

    /**
     * Preloads program code options for all unique sector-productType combinations from Program_Master__c
     * This ensures dropdowns have data available synchronously when rows are created
     */
    async preloadProgramCodeOptionsFromProgramMasters() {
        const sectorProductTypeMap = new Map();
        
        if (this.programMasters && this.programMasters.length > 0) {
            this.programMasters.forEach(pm => {
                if (!pm.Sector__c || !pm.Product__c || !pm.Program_Code__c) {
                    return;
                }

                const key = `${pm.Sector__c}|${pm.Product__c}`;
                if (!sectorProductTypeMap.has(key)) {
                    sectorProductTypeMap.set(key, {
                        authSector: pm.Sector__c,
                        productType: pm.Product__c
                    });
                }
            });
        } else if (this.shopMasters && this.shopMasters.length > 0) {
            this.shopMasters.forEach(shopMaster => {
                if (this.shouldExcludeShop(shopMaster.Auth_Sector__c, shopMaster.Product_Type__c)) {
                    return;
                }
                const key = `${shopMaster.Auth_Sector__c}|${shopMaster.Product_Type__c}`;
                if (!sectorProductTypeMap.has(key)) {
                    sectorProductTypeMap.set(key, {
                        authSector: shopMaster.Auth_Sector__c,
                        productType: shopMaster.Product_Type__c
                    });
                }
            });
        }
        
        sectorProductTypeMap.forEach((sptData, key) => {
            const options = this.getMatchingProgramMasters(sptData.authSector, sptData.productType)
                .map(pm => pm.Program_Code__c)
                .filter(Boolean)
                .filter((value, index, values) => values.indexOf(value) === index)
                .map(code => ({ label: code, value: code }));

            this.programCodeOptionsCache[key] = options;
        });
    }
    
    /**
     * Gets Program Code dropdown options from Program_Master__c for the given sector and product type
     * Uses cache keyed by "authSector|productType"
     */
    getProgramDropdownOptions(authSector, productType) {
        if (!authSector || !productType) {
            return [];
        }
        const key = `${authSector}|${productType}`;
        return this.programCodeOptionsCache[key] || [];
    }

    /**
     * Filters out GPS rows with Product Type Drive Unit or Transmission
     */
    shouldExcludeShop(authSector, productType) {
        // No longer excluding GPS Driver or Transmission
        return false;
    }
    
    /**
     * Determines if Manage Shifts button should be shown
     * Button appears when Program Code, Program Name, and Op Plan all have values
     */
    shouldShowAllocateButton(program, isMasterRow) {
        if (isMasterRow || !program.isVisible) {
            return false;
        }
        
        const hasProgramCode = program.selectedProgramCode && program.selectedProgramCode.trim() !== '';
        const hasProgramName = program.plantProgramName && program.plantProgramName.trim() !== '';
        const hasOpPlan = program.operationPlanId && program.operationPlanId.trim() !== '';
        
        return hasProgramCode && hasProgramName && hasOpPlan;
    }

    /**
     * Ensures Plant_Program_Code__c record exists for the given combination
     * @param {String} authSector - The Auth Sector value
     * @param {String} productType - The Product Type value
     * @param {String} programCode - The Program Code value
     */
    async ensurePlantProgramCodeRecord(authSector, productType, programCode) {
        if (!authSector || !productType || !programCode) {
            return;
        }
        
        try {
            const result = await ensurePlantProgramCodeExists({
                authSector: authSector,
                productType: productType,
                programCode: programCode
            });
            
            if (!result.success) {
                console.warn('Failed to ensure Plant Program Code exists:', result.message);
            }
        } catch (error) {
            console.error('Error ensuring Plant Program Code exists:', error);
        }
    }

    /**
     * Determines if a checkbox should be checked by default
     * Only Program Index A should be checked by default
     * Exception: GPS-Engine Program Index B should be checked (has Gen V program code)
     */
    shouldBeDefaultChecked(authSector, productType, shop, programValue, programCode) {
        const sector = authSector || '';
        const prodType = productType || '';
        const shopValue = shop || '';
        const progIndex = programValue || '';
        const progCode = programCode || '';

        // Only check Program Index A by default (except GPS-Engine Program Index B)
        // For Program Index B+ (except GPS-Engine B), return false
        if (progIndex !== 'A' && !(sector === 'GPS' && prodType === 'Engine' && progIndex === 'B')) {
            return false;
        }

        // Default checked combinations for Program Index A
        const defaults = [
            { sector: 'Assembly', prodType: 'Vehicle', shop: 'All Except Body, Paint', progIndex: 'A', progCode: 'Mid Size SUV' },
            { sector: 'Assembly', prodType: 'Vehicle', shop: 'Body', progIndex: 'A', progCode: 'Mid Size SUV' },
            { sector: 'Assembly', prodType: 'Vehicle', shop: 'Paint', progIndex: 'A', progCode: 'Mid Size SUV' },
            { sector: 'GPS', prodType: 'Engine', shop: 'All', progIndex: 'A', progCode: 'CSS' },
            { sector: 'GPS', prodType: 'Battery', shop: 'All', progIndex: 'A', progCode: 'Ultium' },
            { sector: 'Polymers', prodType: 'Polymers', shop: 'All', progIndex: 'A', progCode: 'Polymers' },
            { sector: 'Press', prodType: 'Press', shop: 'All', progIndex: 'A', progCode: 'Press' }
        ];

        // Special case: GPS-Engine Program Index B should be checked
        if (sector === 'GPS' && prodType === 'Engine' && progIndex === 'B' && progCode === 'Gen V') {
            return true;
        }

        return defaults.some(def => {
            const shopMatches = (def.shop === SHOP_ALL && isShopAll(shopValue)) ||
                (def.shop === SHOP_ALL_EXCEPT_BODY_PAINT && isShopAllExceptBodyPaint(shopValue)) ||
                (def.shop === shopValue);
            return def.sector === sector &&
                def.prodType === prodType &&
                shopMatches &&
                def.progIndex === progIndex &&
                def.progCode === progCode;
        });
    }

    populateDefaultPlantShopRows() {
        let plantShopKeysMap = new Map();
        let plantShopRows = [];
        const plantAuthSector = (this.plantAuthSector || '').trim();

        // Use Program_Master__c as the source of truth for sector/product type combinations
        // Rows = sector/productType that exist in BOTH Plant_Shop__c and Program_Master__c
        const sectorProductTypeMap = new Map();
        
        // If we have Program_Master__c records, use them as the source of truth
        if (this.programMasters && this.programMasters.length > 0) {
            // Get unique sector/product type combinations from Program_Master__c
            this.programMasters.forEach(pm => {
                if (plantAuthSector && pm.Sector__c !== plantAuthSector) {
                    return;
                }
                if (!pm.Sector__c || !pm.Product__c) {
                    return;
                }

                const key = `${pm.Sector__c}|${pm.Product__c}`;
                if (!sectorProductTypeMap.has(key)) {
                    sectorProductTypeMap.set(key, {
                        authSector: pm.Sector__c,
                        productType: pm.Product__c,
                        shops: []
                    });
                }
            });
        } else {
            // Fallback: If no Program_Master__c records, use Shop_Master__c
            // But still filter out excluded shops
            this.shopMasters.forEach(shopMaster => {
                if (plantAuthSector && shopMaster.Auth_Sector__c !== plantAuthSector) {
                    return;
                }
                if (this.shouldExcludeShop(shopMaster.Auth_Sector__c, shopMaster.Product_Type__c)) {
                    return;
                }
                
                const key = `${shopMaster.Auth_Sector__c}|${shopMaster.Product_Type__c}`;
                if (!sectorProductTypeMap.has(key)) {
                    sectorProductTypeMap.set(key, {
                        authSector: shopMaster.Auth_Sector__c,
                        productType: shopMaster.Product_Type__c,
                        shops: []
                    });
                }
            });
        }

        // For each unique sector/product type combination from Program_Master__c,
        // get matching shops from Shop_Master__c
        sectorProductTypeMap.forEach((sptData, key) => {
            const { authSector, productType } = sptData;
            if (plantAuthSector && authSector !== plantAuthSector) {
                return;
            }
            
            // Get shops from Shop_Master__c that match this sector/product type
            const matchingShops = this.getShopsForSectorProductType(authSector, productType);
            
            if (matchingShops.length === 0) {
                return; // Skip if no shops found
            }

            // Group shops appropriately - this applies to ALL plants
            const groupedShops = this.groupShopsForRendering(matchingShops, authSector, productType);
            
            // Create rows for each shop (or accordion row)
            groupedShops.forEach(shopMaster => {
                const shopMasterId = shopMaster.Id;
                const shopKey = shopMasterId;
                
                // Check if this row is expandable
                const isExpandable = this.shouldExpandShop(
                    authSector,
                    productType,
                    shopMaster.Shop__c
                ) !== null;
                
                const shopName = shopMaster.Shop__c || '';
                const showOpPlan = !isShopAll(shopName) && !isShopAllExceptBodyPaint(shopName);
                let newPlantShopRow = {
                    key: shopKey,
                    sortKey: authSector + productType + shopName,
                    plantShopId: null,
                    shopMasterId: shopMasterId,
                    productType: productType || '',
                    shop: shopName,
                    authSector: authSector || '',
                    isExpandable: isExpandable,
                    isExpanded: false,
                    showOpPlan: showOpPlan,
                    showOpPlanColumnClass: showOpPlan ? 'slds-col slds-size_1-of-2' : 'slds-col slds-size_1-of-1',
                    programLoop: this.programValues.map(programValue => {
                        // Get program code from Program_Master__c (if available) or fallback logic
                        const { programCode, programName, showDropdown } = this.getProgramInfo(
                            authSector,
                            productType,
                            shopMaster.Shop__c,
                            programValue
                        );
                        
                        // Get Spring Hill specific program name if applicable
                        // Only for Program Index A (or GPS-Engine Program Index B)
                        let finalProgramName = programName;
                        if (this.plantName && this.plantName.toLowerCase().includes('spring hill') && 
                            (programValue === 'A' || (authSector === 'GPS' && productType === 'Engine' && programValue === 'B'))) {
                            const springHillName = this.getSpringHillProgramName(
                                authSector,
                                productType,
                                programCode,
                                programValue
                            );
                            if (springHillName) {
                                finalProgramName = springHillName;
                            }
                        }
                        
                        const dropdownOptions = (showDropdown || programCode) ? 
                            this.getProgramDropdownOptions(authSector, productType) : [];
                        
                        const isDefaultChecked = this.shouldBeDefaultChecked(
                            authSector,
                            productType,
                            shopMaster.Shop__c,
                            programValue,
                            programCode
                        );
                        
                        const isVisible = shopMaster.Program_Product__c ? 
                            shopMaster.Program_Product__c.includes(programValue) : false;
                        
                        return {
                            programValue: programValue,
                            programCode: programCode,
                            programName: finalProgramName,
                            showDropdown: showDropdown,
                            dropdownOptions: dropdownOptions,
                            selectedProgramCode: programCode || '',
                            plantProgramId: null,
                            plantProgramName: finalProgramName || '', // Set Spring Hill defaults if applicable
                            isVisible: isVisible,
                            isSelected: isDefaultChecked,
                            operationPlanId: '',
                            originalOperationPlanId: '',
                            isChanged: false,
                            showAllocateButton: false,
                            shiftChangeInfo: null,
                            isOpPlanReadOnly: false
                        };
                    }),
                };

                plantShopRows.push(newPlantShopRow);
                plantShopKeysMap.set(shopKey, newPlantShopRow);
            });
        });

        return { plantShopKeysMap, plantShopRows };
    }


    populatePlantShopRows(plantShopRows, plantShopKeysMap) {
        this.plantShops.forEach(plantShop => {
            const key = plantShop.Shop_Master__c;
            let existingPlantShopRow = {};
            if (plantShopKeysMap.has(key)) {
                existingPlantShopRow = plantShopKeysMap.get(key);
                existingPlantShopRow.productType = plantShop.Product_Type__c || '';
                existingPlantShopRow.authSector = plantShop.Auth_Sector__c || '';
                existingPlantShopRow.shop = plantShop.Shop__c || '';
                const shopName = plantShop.Shop__c || '';
                existingPlantShopRow.showOpPlan = !isShopAll(shopName) && !isShopAllExceptBodyPaint(shopName);
                existingPlantShopRow.showOpPlanColumnClass = existingPlantShopRow.showOpPlan ? 'slds-col slds-size_1-of-2' : 'slds-col slds-size_1-of-1';
                existingPlantShopRow.shopMasterId = plantShop.Shop_Master__c;
                existingPlantShopRow.plantShopId = plantShop.Id;
                // Filter Plant Programs to only include original (not cloned) programs
                let filteredPrograms = plantShop.Plant_Programs__r ? 
                    plantShop.Plant_Programs__r.filter(p => this.originalPlantProgramIds.has(p.Id)) : [];
                let hasPrograms = filteredPrograms && filteredPrograms.length > 0;
                existingPlantShopRow.rowColor = hasPrograms ? '' : '';
                if (hasPrograms) {
                    existingPlantShopRow.programLoop.forEach(programLoopRow => {
                        programLoopRow.columnColor = '';
                        programLoopRow.isSelected = false;
                        let program = filteredPrograms.find(p => p.Program_Product_Index__c === programLoopRow.programValue);
                        if (program) {
                            programLoopRow.isVisible = true;
                            programLoopRow.plantProgramId = program.Id;
                            
                            // Always apply defaults from Program_Master__c first (via getProgramInfo)
                            // Then override with existing Plant_Program__c values if they exist
                            // This ensures defaults from Program_Master__c are always calculated
                            const defaultProgramInfo = this.getProgramInfo(
                                existingPlantShopRow.authSector,
                                existingPlantShopRow.productType,
                                existingPlantShopRow.shop,
                                programLoopRow.programValue
                            );
                            
                            // Get Spring Hill specific program name if applicable
                            let defaultProgramName = defaultProgramInfo.programName;
                            if (this.plantName && this.plantName.toLowerCase().includes('spring hill') && 
                                (programLoopRow.programValue === 'A' || 
                                 (existingPlantShopRow.authSector === 'GPS' && existingPlantShopRow.productType === 'Engine' && programLoopRow.programValue === 'B'))) {
                                const springHillName = this.getSpringHillProgramName(
                                    existingPlantShopRow.authSector,
                                    existingPlantShopRow.productType,
                                    defaultProgramInfo.programCode,
                                    programLoopRow.programValue
                                );
                                if (springHillName) {
                                    defaultProgramName = springHillName;
                                }
                            }
                            
                            // When Plant_Program__c exists (e.g. after save), read checkbox from Include__c.
                            // Only populate Program Code, Name, Op Plan when Include__c is true; when false,
                            // show empty values so unchecked rows don't display stale data to other users.
                            programLoopRow.isSelected = program.Include__c === true;

                            if (program.Include__c === true) {
                                programLoopRow.programCode = program.Program_Code__c ?? defaultProgramInfo.programCode ?? '';
                                programLoopRow.selectedProgramCode = program.Program_Code__c ?? defaultProgramInfo.programCode ?? '';
                                programLoopRow.programName = program.Plant_Program_Name__c ?? defaultProgramName ?? '';
                                programLoopRow.plantProgramName = program.Plant_Program_Name__c ?? defaultProgramName ?? '';
                                programLoopRow.originalOperationPlanId = program.Shifts_Def__c ?? '';
                                programLoopRow.operationPlanId = program.Shifts_Def__c ?? '';
                                programLoopRow.isOpPlanReadOnly = !!program.Shifts_Def__c;
                            } else {
                                programLoopRow.programCode = '';
                                programLoopRow.selectedProgramCode = '';
                                programLoopRow.programName = '';
                                programLoopRow.plantProgramName = '';
                                programLoopRow.originalOperationPlanId = '';
                                programLoopRow.operationPlanId = '';
                                programLoopRow.isOpPlanReadOnly = false;
                            }

                            // Update showAllocateButton - show when Program Code, Program Name, and Op Plan all have values
                            const isMasterRow = this.shouldExpandShop(existingPlantShopRow.authSector, existingPlantShopRow.productType, existingPlantShopRow.shop) !== null;
                            programLoopRow.showAllocateButton = this.shouldShowAllocateButton({
                                ...programLoopRow,
                                authSector: existingPlantShopRow.authSector,
                                productType: existingPlantShopRow.productType,
                                shop: existingPlantShopRow.shop
                            }, isMasterRow);
                            
                            // If any program has changes, mark the component as having unsaved changes
                            if (programLoopRow.isChanged) {
                                this.hasUnsavedChanges = true;
                            }
                            
                            console.log('✅ Populated program from existing record:', {
                                programValue: programLoopRow.programValue,
                                programCode: programLoopRow.programCode,
                                programName: programLoopRow.programName,
                                operationPlanId: programLoopRow.operationPlanId,
                                plantProgramId: programLoopRow.plantProgramId,
                                rawProgramData: {
                                    Program_Code__c: program.Program_Code__c,
                                    Plant_Program_Name__c: program.Plant_Program_Name__c
                                }
                            });
                        } else {
                            // No existing program found - log for debugging
                            console.log('⚠️ No existing program found for:', {
                                programValue: programLoopRow.programValue,
                                shopMasterId: existingPlantShopRow.shopMasterId,
                                filteredProgramsCount: filteredPrograms.length
                            });
                        }
                    });
                }
            }
        });
        return plantShopRows;
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(evt);
    }

    // Shift Change Modal Handlers
    handleAuth3rdChange(event) {
        this.auth3rdShiftValue = event.target.value;
    }

    // Computed property for new shift label
    get newShiftLabel() {
        if (this.oldShiftCount === 1 && this.newShiftCount === 2) return '2nd shift';
        if (this.oldShiftCount === 1 && this.newShiftCount === 3) return '2nd and 3rd shifts';
        if (this.newShiftCount === 3) return '3rd shift';
        return 'new shift';
    }

    // Determine which columns should be disabled based on shift change
    get is2ndShiftDisabled() {
        // If changing from 1 to 2 shifts, 2nd shift is editable (NOT disabled)
        // If changing from 2 to 3 shifts, 2nd shift is readonly (disabled)
        return this.oldShiftCount >= 2;
    }

    get is2ndShiftEditable() {
        // 2nd shift is editable when going from 1 to 2 shifts or from 1 to 3 shifts
        return (this.oldShiftCount === 1 && this.newShiftCount === 2) || 
               (this.oldShiftCount === 1 && this.newShiftCount === 3);
    }

    get isGoingFrom1To3() {
        // Helper to check if going from 1 to 3 shifts
        return this.oldShiftCount === 1 && this.newShiftCount === 3;
    }

    get is3rdShiftDisabled() {
        // 3rd shift is editable when changing TO 3 shifts
        return this.newShiftCount !== 3;
    }


    handleShiftValueChange(event) {
        const workbookId = event.target.dataset.id;
        const shift = event.target.dataset.shift; // '2nd' or '3rd'
        const value = parseFloat(event.target.value) || 0;
        
        // Update the specific workbook's shift value based on which shift is being edited
        this.workbookData = this.workbookData.map(wb => {
            if (wb.workbookId === workbookId) {
                if (shift === '2nd') {
                    return { ...wb, newShift2ndValue: value };
                } else {
                    return { ...wb, newShiftValue: value };
                }
            }
            return wb;
        });
    }

    handleCloseShiftModal() {
        this.showShiftChangeModal = false;
        this.pendingShiftChange = null;
        this.auth3rdShiftValue = 0;
        this.workbookData = [];
        this.functionNameFilter = ''; // Clear filter when closing modal
    }

    handleConfirmShiftChange() {
        if (!this.pendingShiftChange) {
            this.showToast('Error', 'Invalid shift change context', 'error');
            return;
        }
        /* Do we still need this validation?
        // Validate that all functions have valid shift values
        let invalidFunctions = [];
        
        if (this.oldShiftCount === 1 && this.newShiftCount === 3) {
            // When going from 1→3, check both 2nd and 3rd shift values
            invalidFunctions = this.plantFunctionsData.filter(func => 
                !func.newShift2ndValue || func.newShift2ndValue <= 0 ||
                !func.newShiftValue || func.newShiftValue <= 0
            );
        } else if (this.oldShiftCount === 1 && this.newShiftCount === 2) {
            // When going from 1→2, check 2nd shift value
            invalidFunctions = this.plantFunctionsData.filter(func => 
                !func.newShift2ndValue || func.newShift2ndValue <= 0
            );
        } else {
            // When going from 2→3, check 3rd shift value
            invalidFunctions = this.plantFunctionsData.filter(func => 
                !func.newShiftValue || func.newShiftValue <= 0
            );
        }

        if (invalidFunctions.length > 0) {
            this.showToast('Error', 'Please enter valid crew counts for all functions', 'error');
            return;
        }
        */
        const { shopMasterId, programValue, newOperationPlanId } = this.pendingShiftChange;

        // Store the workbook-specific shift values
        const workbookShiftValues = {};
        const workbookShift2ndValues = {}; // For 2nd shift when going from 1→3
        
        this.workbookData.forEach(wb => {
            if (this.oldShiftCount === 1 && this.newShiftCount === 3) {
                // Store both 2nd and 3rd shift values when going from 1→3
                workbookShift2ndValues[wb.workbookId] = wb.newShift2ndValue;
                workbookShiftValues[wb.workbookId] = wb.newShiftValue;
            } else if (this.oldShiftCount === 1 && this.newShiftCount === 2) {
                // Store 2nd shift value when going from 1→2
                workbookShift2ndValues[wb.workbookId] = wb.newShift2ndValue;
            } else {
                // Store 3rd shift value when going from 2→3
                workbookShiftValues[wb.workbookId] = wb.newShiftValue;
            }
        });

        // Update the Operation Plan in the data with proper reactivity
        this.plantShopRows = this.plantShopRows.map(row => {
            if (row.key === shopMasterId) {
                return {
                    ...row,
                    programLoop: row.programLoop.map(prog => {
                        if (prog.programValue === programValue) {
                            console.log('Updated program with function-specific shift values');
                            // Create new program object with updated values
                            const originalId = prog.originalOperationPlanId || prog.operationPlanId;
                            const updatedProg = {
                                ...prog,
                                operationPlanId: newOperationPlanId,
                                originalOperationPlanId: originalId, // Preserve original for comparison
                                isChanged: true
                            };
                            
                            // Store workbook shift values based on the shift transition
                            if (Object.keys(workbookShiftValues).length > 0) {
                                updatedProg.workbookShiftValues = workbookShiftValues; // Store 3rd shift values (for 1→3 or 2→3)
                            }
                            if (Object.keys(workbookShift2ndValues).length > 0) {
                                updatedProg.workbookShift2ndValues = workbookShift2ndValues; // Store 2nd shift values (for 1→2 or 1→3)
                            }
                            
                            return updatedProg;
                        }
                        return prog;
                    })
                };
            }
            return row;
        });

        // Close modal
        this.showShiftChangeModal = false;
        this.pendingShiftChange = null;
        this.auth3rdShiftValue = 0;
        this.workbookData = [];
        this.functionNameFilter = ''; // Clear filter when closing modal
        this.clearAllFilters(); // Clear all column filters
        this.showFilterDropdowns = {
            function: false,
            programCode: false,
            functionalArea: false,
            shop: false
        };

        this.showToast('Success', 'Shift values saved for all workbook records', 'success');
    }

    // Getter for dynamic panel header
    get panelHeader() {
        return this.plantName ? `Manage Plant Shops ${this.plantName}` : 'Manage Plant Shops';
    }
    
    /**
     * Determine if Save and Cancel buttons should be disabled
     * Buttons are enabled when:
     * - There are no existing plant programs (new plant setup), OR
     * - Some change has been made
     */
    get isSaveDisabled() {
        // If loading, always disable
        if (this.isLoading) return true;
        
        // Enable if no existing plant programs (new setup)
        if (!this.hasExistingPlantPrograms) return false;
        
        // Enable if there are unsaved changes
        if (this.hasUnsavedChanges) return false;
        
        // Also check if any program has isChanged flag set (in case hasUnsavedChanges wasn't updated)
        const hasAnyChanges = this.plantShopRows && this.plantShopRows.some(row => 
            row.programLoop && row.programLoop.some(prog => prog.isChanged)
        );
        if (hasAnyChanges) return false;
        
        // Otherwise, disable
        return true;
    }
    
    /**
     * Cancel button should also be disabled when there are no changes to undo
     * (unless it's a new plant with no programs - then allow cancel to close)
     */
    get isCancelDisabled() {
        if (this.isLoading) return true;
        
        // If no existing programs, allow cancel to close the modal
        if (!this.hasExistingPlantPrograms) return false;
        
        // If there are changes, allow cancel to undo them
        if (this.hasUnsavedChanges) return false;
        
        // Otherwise, disable (no changes to undo)
        return true;
    }

    // Getter for filtered workbook data based on all column filters
    get filteredWorkbookData() {
        if (!this.workbookData || this.workbookData.length === 0) {
            return [];
        }
        
        return this.workbookData.filter(wb => {
            // Function filter
            if (this.columnFilters.function.length > 0) {
                if (!wb.functionName || !this.columnFilters.function.includes(wb.functionName)) {
                    return false;
                }
            }
            
            // Program Code filter
            if (this.columnFilters.programCode.length > 0) {
                if (!wb.programCode || !this.columnFilters.programCode.includes(wb.programCode)) {
                    return false;
                }
            }
            
            // Functional Area filter
            if (this.columnFilters.functionalArea.length > 0) {
                if (!wb.functionalArea || !this.columnFilters.functionalArea.includes(wb.functionalArea)) {
                    return false;
                }
            }
            
            // Shop filter
            if (this.columnFilters.shop.length > 0) {
                if (!wb.shop || !this.columnFilters.shop.includes(wb.shop)) {
                    return false;
                }
            }
            
            return true;
        });
    }
    
    // Get unique values for each column
    get uniqueFunctionNames() {
        const unique = [...new Set(this.workbookData.map(wb => wb.functionName).filter(Boolean))];
        return unique.sort();
    }
    
    get uniqueProgramCodes() {
        const unique = [...new Set(this.workbookData.map(wb => wb.programCode).filter(Boolean))];
        return unique.sort();
    }
    
    get uniqueFunctionalAreas() {
        const unique = [...new Set(this.workbookData.map(wb => wb.functionalArea).filter(Boolean))];
        return unique.sort();
    }
    
    get uniqueShops() {
        const unique = [...new Set(this.workbookData.map(wb => wb.shop).filter(Boolean))];
        return unique.sort();
    }
    
    // Check if a column has active filters
    get hasActiveFilters() {
        return this.columnFilters.function.length > 0 ||
               this.columnFilters.programCode.length > 0 ||
               this.columnFilters.functionalArea.length > 0 ||
               this.columnFilters.shop.length > 0;
    }
    
    // Handler for function name filter input (deprecated, keeping for backward compatibility)
    handleFunctionNameFilterChange(event) {
        this.functionNameFilter = event.target.value;
    }
    
    // Toggle filter dropdown
    toggleFilterDropdown(event) {
        const columnName = event.currentTarget.dataset.column;
        this.showFilterDropdowns = {
            ...this.showFilterDropdowns,
            [columnName]: !this.showFilterDropdowns[columnName]
        };
    }
    
    // Handle filter checkbox change
    handleFilterChange(event, columnName) {
        const value = event.target.value;
        const checked = event.target.checked;
        
        const currentFilters = [...this.columnFilters[columnName]];
        
        if (checked) {
            if (!currentFilters.includes(value)) {
                currentFilters.push(value);
            }
        } else {
            const index = currentFilters.indexOf(value);
            if (index > -1) {
                currentFilters.splice(index, 1);
            }
        }
        
        this.columnFilters = {
            ...this.columnFilters,
            [columnName]: currentFilters
        };
    }
    
    // Wrapper methods for each column
    handleFilterChangeFunction(event) {
        this.handleFilterChange(event, 'function');
    }
    
    handleFilterChangeProgramCode(event) {
        this.handleFilterChange(event, 'programCode');
    }
    
    handleFilterChangeFunctionalArea(event) {
        this.handleFilterChange(event, 'functionalArea');
    }
    
    handleFilterChangeShop(event) {
        this.handleFilterChange(event, 'shop');
    }
    
    // Select all filters for a column
    selectAllFilters(event) {
        const columnName = event.currentTarget.dataset.column;
        let allValues = [];
        switch(columnName) {
            case 'function':
                allValues = this.uniqueFunctionNames;
                break;
            case 'programCode':
                allValues = this.uniqueProgramCodes;
                break;
            case 'functionalArea':
                allValues = this.uniqueFunctionalAreas;
                break;
            case 'shop':
                allValues = this.uniqueShops;
                break;
        }
        
        this.columnFilters = {
            ...this.columnFilters,
            [columnName]: [...allValues]
        };
    }
    
    // Clear all filters for a column
    clearColumnFilter(event) {
        const columnName = event.currentTarget.dataset.column;
        this.columnFilters = {
            ...this.columnFilters,
            [columnName]: []
        };
    }
    
    // Clear all filters
    clearAllFilters() {
        this.columnFilters = {
            function: [],
            programCode: [],
            functionalArea: [],
            shop: []
        };
        this.functionNameFilter = '';
    }
    
    // Check if a filter value is selected - returns a function for template use
    isFilterSelected(columnName, value) {
        return this.columnFilters[columnName].includes(value);
    }
    
    // Handler for function filter checkbox - checks value from event
    handleFilterChangeFunction(event) {
        const value = event.target.value;
        const checked = event.target.checked;
        
        const currentFilters = [...this.columnFilters.function];
        
        if (checked) {
            if (!currentFilters.includes(value)) {
                currentFilters.push(value);
            }
        } else {
            const index = currentFilters.indexOf(value);
            if (index > -1) {
                currentFilters.splice(index, 1);
            }
        }
        
        this.columnFilters = {
            ...this.columnFilters,
            function: currentFilters
        };
    }
    
    
    // Handler for program code filter checkbox
    handleFilterChangeProgramCode(event) {
        this.handleFilterChange(event, 'programCode');
    }
    
    // Handler for functional area filter checkbox
    handleFilterChangeFunctionalArea(event) {
        this.handleFilterChange(event, 'functionalArea');
    }
    
    // Handler for shop filter checkbox
    handleFilterChangeShop(event) {
        this.handleFilterChange(event, 'shop');
    }
    
    // Getters that return Sets of selected values for template checking
    get selectedFunctionFilters() {
        return new Set(this.columnFilters.function);
    }
    
    get selectedProgramCodeFilters() {
        return new Set(this.columnFilters.programCode);
    }
    
    get selectedFunctionalAreaFilters() {
        return new Set(this.columnFilters.functionalArea);
    }
    
    get selectedShopFilters() {
        return new Set(this.columnFilters.shop);
    }
    
    // Get filter count for a column
    getFilterCount(columnName) {
        return this.columnFilters[columnName].length;
    }
    
    // Get filter icon class based on whether column has active filters
    get getFilterIconClass() {
        return {
            function: this.columnFilters.function.length > 0 ? 'excel-filter-icon-active' : '',
            programCode: this.columnFilters.programCode.length > 0 ? 'excel-filter-icon-active' : '',
            functionalArea: this.columnFilters.functionalArea.length > 0 ? 'excel-filter-icon-active' : '',
            shop: this.columnFilters.shop.length > 0 ? 'excel-filter-icon-active' : ''
        };
    }
}