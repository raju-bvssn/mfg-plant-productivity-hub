import { LightningElement, api, wire } from 'lwc';
import getPlantProgramData from '@salesforce/apex/FunctionMasterController.getPlantProgramData';

export default class FunctionMasterRelatedList extends LightningElement {
    @api recordId;
    @api objectApiName;
    data;
    error;
    _effectiveRecordId;

    connectedCallback() {
        // Get recordId from @api property or extract from URL
        this._effectiveRecordId = this.recordId || this.getRecordIdFromUrl();
        console.log('Effective RecordId => ', this._effectiveRecordId);
    }

    getRecordIdFromUrl() {
        const url = window.location.href;
        // Match Salesforce 15 or 18 character record IDs in the URL
        const recordIdMatch = url.match(/\/([a-zA-Z0-9]{15,18})(?:\/|$|\?)/);
        return recordIdMatch ? recordIdMatch[1] : null;
    }

    get functionId() {
        // Use the effective recordId (from @api or URL)
        return this._effectiveRecordId || this.recordId;
    }

    @wire(getPlantProgramData, { functionId: '$functionId' })
    wiredData({ data, error }) {
        if (data) {
            console.log('Successfully fetched data for RecordId:', this.functionId);
            this.data = data;
            this.error = undefined;
        } else if (error) {
            console.error('Error fetching data:', error);
            this.error = error;
            this.data = undefined;
        }
    }

    get hasPlanOfRecord() {
        return this.data && this.data['Plan of Record'];
    }

    get hasStudy() {
        return this.data && this.data['Study'];
    }

    get planOfRecord() {
        return this.data ? this.data['Plan_of_Record'] : null;
    }

    get study() {
        return this.data ? this.data['Study'] : null;
    }
}