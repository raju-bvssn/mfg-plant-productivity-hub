import { api, LightningElement } from 'lwc';

export default class CustomNumberEdit extends LightningElement {
    @api value;
    @api context;
    @api rowId; // Row Id from the datatable

    handleChange(event) {
        const newValue = event.target.value ? parseFloat(event.target.value) : 0;
        // Get the field name from context (should be the field name string)
        const fieldName = typeof this.context === 'string' ? this.context : 'value';
        
        // Dispatch onvaluechange event that lightning-datatable expects
        // The datatable will automatically add the Id based on key-field
        this.dispatchEvent(new CustomEvent('onvaluechange', {
            composed: true,
            bubbles: true,
            cancelable: true,
            detail: {
                value: newValue
            }
        }));
    }

    handleBlur() {
        // Dispatch blur to close the edit mode
        this.dispatchEvent(new CustomEvent('ieditfinished', {
            composed: true,
            bubbles: true
        }));
    }
}