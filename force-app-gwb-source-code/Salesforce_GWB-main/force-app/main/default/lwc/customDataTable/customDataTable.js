import LightningDatatable from 'lightning/datatable';
import customPicklistTemplate from './customPicklist.html';
import customPicklistEditTemplate from './customPicklistEdit.html';
import customNumberTemplate from './customNumber.html';
import customNumberEditTemplate from './customNumberEdit.html';

export default class CustomDataTable extends LightningDatatable {
    static customTypes = {
        picklistColumn: {
            template: customPicklistTemplate,
            editTemplate: customPicklistEditTemplate,
            standardCellLayout: true,
            typeAttributes: ['options', 'value', 'placeholder', 'context']
        },
        compactNumber: {
            template: customNumberTemplate,
            editTemplate: customNumberEditTemplate,
            standardCellLayout: true,
            typeAttributes: ['value', 'context']
        }
    };
}