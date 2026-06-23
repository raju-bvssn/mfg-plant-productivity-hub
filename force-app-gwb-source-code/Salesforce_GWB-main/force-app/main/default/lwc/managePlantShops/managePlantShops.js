/**
 * @description       : Manage Plant Shops Quick Action Component
 * @group             : 
 * @last modified on  : 01-15-2025
 * @last modified by  : 
**/
import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from "lightning/refresh";
import LightningConfirm from 'lightning/confirm';

import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import CUSTOM_MODAL_CSS from '@salesforce/resourceUrl/QuickActionWidthFixCss'; // Replace CustomModalWidthCSS with your static resource name



import getInitialData from '@salesforce/apex/ManagePlantShopsController.getInitialData';
import savePrograms from '@salesforce/apex/ManagePlantShopsController.savePrograms';
import savePlantShops from '@salesforce/apex/ManagePlantShopsController.savePlantShops';
import createPlantFunctions from '@salesforce/apex/ManagePlantShopsController.createPlantFunctions';

export default class ManagePlantShops extends LightningElement {
    @api recordId; // Plant ID from quick action context

    isLoading = false;
    @track error;

    plantShops = [];
    shopMasters = [];
    shopPrograms = [];

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

    // Use imperative call inside connectedCallback, with dataLoad flag to ensure single load
    dataLoaded = false;

    connectedCallback() {
        Promise.all([
            loadStyle(this, CUSTOM_MODAL_CSS)
        ]).then(() => {
            console.log('Styles loaded successfully');
        }).catch(error => {
            console.error('Error loading styles:', error);
        });
    }

    @wire(CurrentPageReference)
    getPageReferenceParameters(currentPageReference) {
        if (currentPageReference) {
            console.log(currentPageReference);
            console.log('currentPageReference', JSON.parse(JSON.stringify(currentPageReference)));
            this.recordId = currentPageReference.state.recordId;
            this.isLoading = true;
            getInitialData({ plantId: this.recordId })
                .then(data => {
                    console.log('data', JSON.parse(JSON.stringify(data)));
                    this.plantShops = data.plantShops || [];
                    this.shopMasters = data.shopMasters || [];
                    this.shopPrograms = data.shopPrograms || [];


                    // Populate plantShopRows and get mapping of keys to rows
                    let { plantShopKeysMap, plantShopRows } = this.populateDefaultPlantShopRows();

                    console.log('plantShopKeysMap', JSON.parse(JSON.stringify(plantShopKeysMap)));
                    console.log('plantShopRows', JSON.parse(JSON.stringify(plantShopRows)));

                    plantShopRows = this.populatePlantShopRows(plantShopRows, plantShopKeysMap);
                    console.log('plantShopRows after processing', JSON.parse(JSON.stringify(plantShopRows)));

                    this.plantShopRows = plantShopRows.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
                    console.log('plantShopRows after sort', JSON.parse(JSON.stringify(this.plantShopRows)));

                    this.isLoading = false;
                })
                .catch(error => {
                    this.error = error?.body?.message || error?.message || 'Failed to load initial data.';
                    console.log('Error', JSON.parse(JSON.stringify(error)));
                });
        }
    }


    handleOperationPlanChange(event) {
        const { key: shopMasterId, program: programValue } = event.target.dataset;
        const operationPlanId = event.detail.recordId;
        console.log('Selected Operation Plan ID:', operationPlanId);
        console.log('Shop Master ID:', shopMasterId);
        console.log('Program Value:', programValue);

        const plantShops = this.plantShopRows;
        const plantShop = plantShops.find(r => r.key === shopMasterId);
        if (!plantShop) {
            console.warn(`[handleOperationPlanChange] Row not found for key: ${shopMasterId}`);
            return;
        }

        plantShop.programLoop.find(p => p.programValue === programValue).operationPlanId = operationPlanId;
        console.log('Updated Plant Shop:', JSON.parse(JSON.stringify(plantShop)));
        this.plantShopRows = plantShops;
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

        // Check if we need to show warning for deactivation
        if (!userInput && program.plantProgramId) {
            const result = await LightningConfirm.open({
                message: 'Deactivating this existing program will also archive its related functions.',
                variant: 'header',
                label: 'Deactivation Warning',
                theme: 'warning'
            });
            console.log('result', JSON.parse(JSON.stringify(result)));
            if (!result) {
                // User cancelled, revert checkbox via DOM (manual rollback)
                // Because the property update is not sufficient (LWC reactivity quirk),
                // we must also update the DOM directly to properly reflect checkbox state.
                // eslint-disable-next-line lwc/no-document-query
                // Get the checkbox input using querySelector from the event row context
                // Find the input with matching program and key (data attributes)
                const selector = `lightning-input[data-program="${programValue}"][data-key="${shopMasterId}"]`;
                const input = this.template.querySelector(selector);
                if (input) {
                    input.checked = true;
                }
                // const input = event.target;
                // if (input && input.type === 'checkbox') {
                //     input.checked = true;
                // }
                console.log('System Input Prevail');
                return;
            }
        }
        console.log('User Input Prevail');
        // Update state
        program.isSelected = userInput;
        program.isChanged = true;

        // Trigger reactivity by reassigning the array
        this.plantShopRows = plantShops;
    }

    async handleSave() {
        try {
            this.isLoading = true;
            console.log('plantShopRows', JSON.parse(JSON.stringify(this.plantShopRows)));

            // 1. Prepare and insert new Plant Shops if needed
            const shopDataList = this.prepareShopDataList();
            console.log('shopDataList', JSON.parse(JSON.stringify(shopDataList)));

            console.log('Task 1 Started: Inserting Plant Shops if Needed');
            const insertResult = await this.insertPlantShopsIfNeeded(shopDataList);
            console.log('Task 1 Done: Plant Shop insert result', JSON.parse(JSON.stringify(insertResult)));

            // 2. Prepare Program Data List for Saving
            console.log('Task 2 Started: Preparing Program Data List');
            const programDataList = this.prepareProgramDataList(insertResult);
            console.log('Completed Program Data preparation', JSON.parse(JSON.stringify(programDataList)));

            // 3. Save Programs
            const saveResult = await savePrograms({ programDataListString: JSON.stringify(programDataList) });
            console.log('Task 2 Done: savePrograms result', JSON.parse(JSON.stringify(saveResult)));

            // 4. Create Plant Functions
            await this.handleCreatePlantFunctions(saveResult);
            console.log('Task 3 Done: createPlantFunctions result');


            // 5. Refresh and Close
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(new CloseActionScreenEvent());

            // 6. Show Success Toast
            this.showToast('Success', 'Records saved successfully', 'success');

        } catch (error) {
            console.error('Save Error:', JSON.parse(JSON.stringify(error)));
            this.showToast('Error', error?.body?.message || error?.message || 'An error occurred during save', 'error');
        } finally {
            console.log('All Tasks Finished. Setting isLoading to false');
            this.isLoading = false;
        }
    }

    prepareShopDataList() {
        const shopDataList = [];
        (this.plantShopRows || []).forEach(plantShopRow => {
            if (plantShopRow.plantShopId === null) {
                shopDataList.push({
                    plantId: this.recordId,
                    shopMasterId: plantShopRow.shopMasterId
                });
            }
        });
        return shopDataList;
    }

    prepareProgramDataList(insertResult) {
        let programDataList = [];
        console.log('Task 2 Detail: Preparing Program Data List', JSON.parse(JSON.stringify(this.plantShopRows)));
        this.plantShopRows.forEach(plantShopRow => {

            let plantShopId = plantShopRow.plantShopId;
            if (!plantShopId) {
                plantShopId = insertResult.shopMasterIdToPlantShopIdMap?.[plantShopRow.shopMasterId];
            }
            console.log('Determined plantShopId', plantShopId);

            plantShopRow.programLoop.forEach(program => {
                if (!program.isVisible) return;

                if (!program.plantProgramId && program.isSelected) {
                    console.log('Queued for INSERT PROGRAM', JSON.parse(JSON.stringify(program)));
                    programDataList.push({
                        plantProgramId: null,
                        plantId: this.recordId,
                        plantShopId: plantShopId,
                        programValue: program.programValue,
                        isSelected: program.isSelected,
                        operationPlanId: program.operationPlanId
                    });
                } else if (program.isChanged) {
                    console.log('Queued for UPDATE PROGRAM', JSON.parse(JSON.stringify(program)));
                    programDataList.push({
                        plantProgramId: program.plantProgramId,
                        plantId: this.recordId,
                        plantShopId: plantShopId,
                        programValue: program.programValue,
                        isSelected: program.isSelected,
                        operationPlanId: program.operationPlanId
                    });
                }
            });
        });
        return programDataList;
    }

    async handleCreatePlantFunctions(saveResult) {
        if (saveResult.success && saveResult.programIds && saveResult.programIds.length > 0) {
            console.log('Task 3 Started: Creating Plant Functions for new Program IDs', JSON.parse(JSON.stringify(saveResult.programIds)));
            const result = await createPlantFunctions({ plantProgramIds: saveResult.programIds });
            console.log('Task 3 Done: createPlantFunctions result', JSON.parse(JSON.stringify(result)));
            return result;
        } else {
            console.log('Task 3 Skipped: No Plant Programs to create functions for.');
            return { success: true, message: 'No plant programs to create functions for.' };
        }
    }


    /**
     * Inserts plant shops if shopDataList is provided and not empty.
     * Returns a promise resolving with the save result or a success message if nothing to insert.
     */
    async insertPlantShopsIfNeeded(shopDataList) {
        console.log('insertPlantShopsIfNeeded', JSON.parse(JSON.stringify(shopDataList)));
        if (!Array.isArray(shopDataList) || shopDataList.length === 0) {
            console.log('No shops to insert.');
            return { success: true, message: 'No shops to insert.' };
        }

        try {
            const result = await savePlantShops({ shopDataListString: JSON.stringify(shopDataList) });
            console.log('savePlantShops result', JSON.parse(JSON.stringify(result)));
            return result;
        } catch (error) {
            console.error('insertPlantShopsIfNeeded error', JSON.parse(JSON.stringify(error)));
            throw error;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    populateDefaultPlantShopRows() {
        let plantShopKeysMap = new Map();
        let plantShopRows = [];

        this.shopMasters.forEach(shopMaster => {
            let shopMasterId = shopMaster.Id;
            let key = shopMasterId;
            let newPlantShopRow = {
                key: shopMasterId,
                sortKey: shopMaster.Auth_Sector__c + shopMaster.Product_Type__c + shopMaster.Shop__c,
                plantShopId: null,
                shopMasterId: shopMasterId,
                productType: shopMaster.Product_Type__c || '',
                shop: shopMaster.Shop__c || '',
                authSector: shopMaster.Auth_Sector__c || '',
                programLoop: this.programValues.map(programValue => ({
                    programValue: programValue,
                    plantProgramId: null,
                    isVisible: shopMaster.Program_Product__c ? shopMaster.Program_Product__c.includes(programValue) : false,
                    isSelected: shopMaster.Default_Program__c ? shopMaster.Default_Program__c.includes(programValue) : false,
                    operationPlanId: null,
                    isChanged: false
                })),
            }

            plantShopRows.push(newPlantShopRow);
            plantShopKeysMap.set(key, newPlantShopRow);
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
                existingPlantShopRow.shopMasterId = plantShop.Shop_Master__c;
                existingPlantShopRow.plantShopId = plantShop.Id;
                let hasPrograms = plantShop.Plant_Programs__r && plantShop.Plant_Programs__r.length > 0;
                existingPlantShopRow.rowColor = hasPrograms ? '' : '';
                if (hasPrograms) {
                    existingPlantShopRow.programLoop.forEach(programLoopRow => {
                        programLoopRow.columnColor = '';
                        programLoopRow.isSelected = false;
                        let program = plantShop.Plant_Programs__r.find(p => p.Program_Product_Index__c === programLoopRow.programValue);
                        if (program) {
                            programLoopRow.isVisible = true;
                            programLoopRow.plantProgramId = program.Id;
                            programLoopRow.isSelected = program.Include__c;
                            programLoopRow.operationPlanId = program.Shifts_Def__c;
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
}