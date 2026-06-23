import { LightningElement, api } from 'lwc';

export default class CustomPicklistEdit extends LightningElement {
    @api value;
    @api options;
    @api placeholder;
    @api typeAttributes;

    get currentValue() {
        // The datatable resolves fieldName references and passes the actual value
        return this.value !== undefined && this.value !== null ? this.value : '';
    }

    get currentOptions() {
        // The datatable resolves { fieldName: 'newDriverOptions' } and passes the actual array as 'options'
        console.log('CustomPicklistEdit - currentOptions called');
        console.log('CustomPicklistEdit - this.options:', this.options);
        console.log('CustomPicklistEdit - this.typeAttributes:', this.typeAttributes);
        
        // Check both direct property and typeAttributes
        if (this.options && Array.isArray(this.options) && this.options.length > 0) {
            console.log('CustomPicklistEdit - returning this.options:', this.options);
            return this.options;
        }
        // Fallback: check if typeAttributes has the resolved options
        if (this.typeAttributes?.options && Array.isArray(this.typeAttributes.options)) {
            console.log('CustomPicklistEdit - returning typeAttributes.options:', this.typeAttributes.options);
            return this.typeAttributes.options;
        }
        console.log('CustomPicklistEdit - returning empty array');
        return [];
    }

    get currentPlaceholder() {
        return this.placeholder || this.typeAttributes?.placeholder || 'Select New Driver';
    }

    handleChange(event) {
        const selectedValue = event.detail.value;
        console.log('CustomPicklistEdit handleChange - selectedValue:', selectedValue);
        
        // Dispatch the onvaluechange event that lightning-datatable expects
        // This event format matches what lightning-datatable uses for custom editable types
        const valueChangeEvent = new CustomEvent('onvaluechange', {
            composed: true,
            bubbles: true,
            cancelable: true,
            detail: {
                value: selectedValue
            }
        });
        
        console.log('CustomPicklistEdit dispatching onvaluechange event:', valueChangeEvent);
        this.dispatchEvent(valueChangeEvent);
    }
}