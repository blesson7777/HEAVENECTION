(function () {
    const modalNode = document.getElementById("heavenectionConfirmModal");
    if (!modalNode || !window.bootstrap) {
        return;
    }

    const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
    const titleNode = modalNode.querySelector("[data-confirm-title]");
    const bodyNode = modalNode.querySelector("[data-confirm-body]");
    const confirmButton = modalNode.querySelector("[data-confirm-ok]");
    let resolver = null;

    function setContent(options) {
        const opts = options || {};
        if (titleNode) {
            titleNode.textContent = opts.title || "Please confirm";
        }
        if (bodyNode) {
            bodyNode.textContent = opts.message || "Are you sure you want to continue?";
        }
        if (confirmButton) {
            confirmButton.textContent = opts.confirmText || "Confirm";
            confirmButton.className = `btn ${opts.confirmClass || "btn-danger"}`;
        }
    }

    function confirmAction(options) {
        return new Promise((resolve) => {
            resolver = resolve;
            setContent(options);
            modal.show();
        });
    }

    if (confirmButton) {
        confirmButton.addEventListener("click", () => {
            if (resolver) {
                resolver(true);
                resolver = null;
            }
            modal.hide();
        });
    }

    modalNode.addEventListener("hidden.bs.modal", () => {
        if (resolver) {
            resolver(false);
            resolver = null;
        }
    });

    window.heavenectionConfirm = confirmAction;

    document.addEventListener("submit", (event) => {
        const form = event.target.closest("form");
        if (!form) {
            return;
        }
        const message = form.dataset.confirmMessage;
        if (!message) {
            return;
        }
        event.preventDefault();
        confirmAction({
            title: form.dataset.confirmTitle || "Please confirm",
            message,
            confirmText: form.dataset.confirmOk || "Confirm",
            confirmClass: form.dataset.confirmClass || "btn-danger",
        }).then((confirmed) => {
            if (confirmed) {
                form.submit();
            }
        });
    });
})();
