({
    // Fired by the LWC whenever its uncommitted inline-edit state changes.
    // Hands control of the unsaved state to Lightning Experience so the
    // "unsaved changes" prompt appears when the user navigates away.
    handleUnsavedChange: function (cmp, event) {
        var unsaved = cmp.find("unsavedChanges");
        var hasUnsavedChanges = event.getParam("hasUnsavedChanges");
        var label = event.getParam("label");
        unsaved.setUnsavedChanges(hasUnsavedChanges === true, { label: label });
    },

    // User chose "Save" in the unsaved-changes prompt. Run the LWC save and
    // return control to Lightning, keeping the unsaved flag set if it failed.
    handleUnsavedSave: function (cmp, event) {
        var unsaved = cmp.find("unsavedChanges");
        var planner = cmp.find("planner");
        Promise.resolve(planner.save())
            .then(function (saved) {
                unsaved.setUnsavedChanges(saved !== true);
            })
            .catch(function () {
                unsaved.setUnsavedChanges(true);
            });
    },

    // User chose "Discard" in the unsaved-changes prompt. Refresh the record
    // from the server, dropping any uncommitted edits, then clear the flag.
    handleUnsavedDiscard: function (cmp, event) {
        var unsaved = cmp.find("unsavedChanges");
        var planner = cmp.find("planner");
        Promise.resolve(planner.discard())
            .then(function () {
                unsaved.setUnsavedChanges(false);
            })
            .catch(function () {
                unsaved.setUnsavedChanges(false);
            });
    }
})
