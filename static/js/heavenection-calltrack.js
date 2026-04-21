(function () {
    function updateClock() {
        const clockNode = document.getElementById("mfHeaderClock");
        if (!clockNode) {
            return;
        }
        const valueNode = clockNode.querySelector(".mf-header-clock-value");
        const now = new Date();
        const timeText = now.toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
            hour12: true,
        });
        const dateText = now.toLocaleDateString([], {
            weekday: "short",
            day: "2-digit",
            month: "short",
            year: "numeric",
        });
        if (valueNode) {
            valueNode.textContent = timeText;
        }
        clockNode.title = dateText;
    }

    function animateCounters() {
        const counters = document.querySelectorAll(".hc-animate-value[data-count]");
        counters.forEach((counter) => {
            const targetValue = Number(counter.dataset.count || 0);
            if (!Number.isFinite(targetValue)) {
                return;
            }
            const startTime = performance.now();
            const duration = 900;

            function drawFrame(now) {
                const progress = Math.min((now - startTime) / duration, 1);
                const eased = 1 - Math.pow(1 - progress, 3);
                counter.textContent = Math.round(targetValue * eased).toLocaleString("en-IN");
                if (progress < 1) {
                    window.requestAnimationFrame(drawFrame);
                }
            }

            window.requestAnimationFrame(drawFrame);
        });
    }

    function getCsrfToken() {
        const explicitToken = window.heavenectionAdmin?.csrfToken;
        if (explicitToken && explicitToken !== "NOTPROVIDED") {
            return explicitToken;
        }

        const tokenCookie = document.cookie
            .split(";")
            .map((part) => part.trim())
            .find((part) => part.startsWith("csrftoken="));
        if (!tokenCookie) {
            return "";
        }
        return decodeURIComponent(tokenCookie.split("=")[1] || "");
    }

    async function requestJson(url, options) {
        let response;
        try {
            response = await fetch(url, {
                credentials: "same-origin",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRFToken": getCsrfToken(),
                    ...(options?.headers || {}),
                },
                ...options,
            });
        } catch (error) {
            window.heavenectionNetworkState?.show(
                "Connection interrupted. Please wait while the page reconnects.",
            );
            throw new Error("Connection interrupted.");
        }

        let payload = null;
        try {
            payload = await response.json();
        } catch (error) {
            payload = null;
        }

        if (!response.ok) {
            throw new Error(payload ? extractErrorMessage(payload) : "Something went wrong. Please try again.");
        }

        return payload;
    }

    async function requestForm(url, formData, options) {
        let response;
        try {
            response = await fetch(url, {
                credentials: "same-origin",
                headers: {
                    "Accept": "application/json",
                    "X-CSRFToken": getCsrfToken(),
                    ...(options?.headers || {}),
                },
                ...options,
                body: formData,
            });
        } catch (error) {
            window.heavenectionNetworkState?.show(
                "Connection interrupted. Please wait while the page reconnects.",
            );
            throw new Error("Connection interrupted.");
        }

        let payload = null;
        try {
            payload = await response.json();
        } catch (error) {
            payload = null;
        }

        if (!response.ok) {
            throw new Error(payload ? extractErrorMessage(payload) : "Something went wrong. Please try again.");
        }

        return payload;
    }

    async function confirmAction(message, options) {
        if (typeof window.heavenectionConfirm === "function") {
            return window.heavenectionConfirm({ message, ...(options || {}) });
        }
        return window.confirm(message);
    }

    function extractErrorMessage(payload) {
        if (!payload || typeof payload !== "object") {
            return "Unable to complete the request right now.";
        }
        if (payload.detail) {
            return String(payload.detail);
        }
        const firstKey = Object.keys(payload)[0];
        if (!firstKey) {
            return "Unable to complete the request right now.";
        }
        const value = payload[firstKey];
        if (Array.isArray(value) && value.length) {
            return String(value[0]);
        }
        return String(value);
    }

    function escapeHtml(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#39;");
    }

    function storeFlashMessage(message, level) {
        if (!window.sessionStorage) {
            return;
        }
        window.sessionStorage.setItem(
            "heavenectionFlash",
            JSON.stringify({
                message,
                level: level || "success",
            }),
        );
    }

    function renderStoredFlashMessage() {
        if (!window.sessionStorage) {
            return;
        }
        const target = document.getElementById("heavenectionClientFlash");
        const raw = window.sessionStorage.getItem("heavenectionFlash");
        if (!target || !raw) {
            return;
        }

        window.sessionStorage.removeItem("heavenectionFlash");
        try {
            const payload = JSON.parse(raw);
            const level = payload.level === "error" ? "danger" : payload.level;
            target.innerHTML = `
                <div class="hc-page-flash-stack">
                    <div class="alert alert-${level} alert-dismissible fade show" role="alert">
                        ${payload.message}
                        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                    </div>
                </div>
            `;
        } catch (error) {
            window.sessionStorage.removeItem("heavenectionFlash");
        }
    }

    function bindSearchAndFilters() {
        const setups = [
            { inputId: "leadSearchInput", tableBodyId: "leadTableBody" },
            { inputId: "followupSearchInput", tableBodyId: "followupTableBody" },
            { inputId: "callbackSearchInput", tableBodyId: "callbackTableBody" },
            { inputId: "recoverySearchInput", tableBodyId: "recoveryTableBody" },
            { inputId: "callSearchInput", tableBodyId: "callTableBody" },
            { inputId: "staffSearchInput", tableBodyId: "staffTableBody" },
            { inputId: "learningSearchInput", tableBodyId: "learningTableBody" },
            { inputId: "hoursSearchInput", tableBodyId: "hoursSummaryBody" },
            { inputId: "salarySearchInput", tableBodyId: "salaryTableBody" },
            { inputId: "salaryControlSearchInput", tableBodyId: "salaryControlBody" },
        ];

        setups.forEach(({ inputId, tableBodyId }) => {
            const tableBody = document.getElementById(tableBodyId);
            if (!tableBody) {
                return;
            }

            const rows = Array.from(tableBody.querySelectorAll("tr"));
            const searchInput = document.getElementById(inputId);
            const chips = Array.from(document.querySelectorAll(".hc-filter-chip"));

            function render() {
                const query = (searchInput?.value || "").trim().toLowerCase();
                const activeChip = document.querySelector(".hc-filter-chip.is-active");
                const activeStatus = activeChip?.dataset.filterStatus || "all";

                rows.forEach((row) => {
                    const rowText = row.textContent.toLowerCase();
                    const matchesQuery = !query || rowText.includes(query);
                    const rowStatus = row.dataset.status || "all";
                    const matchesStatus = activeStatus === "all" || rowStatus === activeStatus;
                    row.hidden = !(matchesQuery && matchesStatus);
                });
            }

            searchInput?.addEventListener("input", render);
            chips.forEach((chip) => {
                chip.addEventListener("click", () => {
                    chips.forEach((item) => item.classList.remove("is-active"));
                    chip.classList.add("is-active");
                    render();
                });
            });
            render();
        });
    }

    function readPayload() {
        const node = document.getElementById("heavenectionDashboardPayload");
        if (!node) {
            return null;
        }
        try {
            return JSON.parse(node.textContent);
        } catch (error) {
            return null;
        }
    }

    function readJsonScript(id) {
        const node = document.getElementById(id);
        if (!node) {
            return null;
        }
        try {
            return JSON.parse(node.textContent);
        } catch (error) {
            return null;
        }
    }

    function renderCharts() {
        const payload = readPayload();
        if (typeof Chart === "undefined" || !payload) {
            return;
        }

        const gridColor = "rgba(77, 92, 144, 0.16)";
        const textColor = "#334155";
        const surface = "#ffffff";
        const leadPipelineChart = document.getElementById("leadPipelineChart");
        const callVolumeChart = document.getElementById("callVolumeChart");
        const activityBalanceChart = document.getElementById("activityBalanceChart");

        if (!leadPipelineChart || !callVolumeChart || !activityBalanceChart) {
            return;
        }

        new Chart(leadPipelineChart, {
            type: "doughnut",
            data: {
                labels: payload.leadPipeline.labels,
                datasets: [{
                    data: payload.leadPipeline.values,
                    backgroundColor: ["#4d5c90", "#6f80ba", "#f0a53a", "#a9b2cf", "#2d9d68"],
                    borderColor: surface,
                    borderWidth: 4,
                }],
            },
            options: {
                plugins: { legend: { position: "bottom", labels: { color: textColor } } },
                cutout: "64%",
            },
        });

        new Chart(callVolumeChart, {
            type: "line",
            data: {
                labels: payload.callVolume.labels,
                datasets: [
                    {
                        label: "Calls",
                        data: payload.callVolume.calls,
                        borderColor: "#4d5c90",
                        backgroundColor: "rgba(77, 92, 144, 0.18)",
                        fill: true,
                        tension: 0.28,
                    },
                    {
                        label: "Conversions",
                        data: payload.callVolume.conversions,
                        borderColor: "#6f80ba",
                        backgroundColor: "rgba(111, 128, 186, 0.12)",
                        fill: true,
                        tension: 0.28,
                    },
                ],
            },
            options: {
                plugins: { legend: { labels: { color: textColor } } },
                scales: {
                    y: { beginAtZero: true, grid: { color: gridColor }, ticks: { color: textColor } },
                    x: { grid: { display: false }, ticks: { color: textColor } },
                },
            },
        });

        new Chart(activityBalanceChart, {
            type: "bar",
            data: {
                labels: payload.activityBalance.labels,
                datasets: [
                    {
                        label: "Active Hours",
                        data: payload.activityBalance.activeHours,
                        backgroundColor: "#4d5c90",
                        borderRadius: 8,
                    },
                    {
                        label: "Call Minutes",
                        data: payload.activityBalance.callMinutes,
                        backgroundColor: "#8d9dcf",
                        borderRadius: 8,
                    },
                ],
            },
            options: {
                plugins: { legend: { labels: { color: textColor } } },
                scales: {
                    y: { beginAtZero: true, grid: { color: gridColor }, ticks: { color: textColor } },
                    x: { grid: { display: false }, ticks: { color: textColor } },
                },
            },
        });
    }

    function bindStaffCrud() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("staffModal");
        const form = document.getElementById("staffForm");
        if (!config?.teamMembersUrl || !modalNode || !form) {
            return;
        }

        const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
        const titleNode = document.getElementById("staffModalTitle");
        const idInput = document.getElementById("staffFormId");
        const nameInput = document.getElementById("staffName");
        const phoneInput = document.getElementById("staffPhone");
        const passwordInput = document.getElementById("staffPassword");
        const hourlyRateInput = document.getElementById("staffHourlyRate");
        const callRateInput = document.getElementById("staffCallRate");
        const bonusInput = document.getElementById("staffBonus");
        const isActiveInput = document.getElementById("staffIsActive");
        const feedback = document.getElementById("staffFormFeedback");
        const submitButton = document.getElementById("staffSubmitButton");

        function showFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        function resetForm() {
            form.reset();
            idInput.value = "";
            hourlyRateInput.value = "150";
            callRateInput.value = "3";
            bonusInput.value = "500";
            isActiveInput.checked = true;
            titleNode.textContent = "Add Staff Member";
            passwordInput.required = true;
            clearFeedback();
        }

        document.getElementById("openCreateStaffModal")?.addEventListener("click", resetForm);
        modalNode.addEventListener("hidden.bs.modal", clearFeedback);

        document.querySelectorAll(".js-edit-staff").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback();
                idInput.value = button.dataset.staffId || "";
                nameInput.value = button.dataset.name || "";
                phoneInput.value = button.dataset.phone || "";
                passwordInput.value = "";
                passwordInput.required = false;
                hourlyRateInput.value = button.dataset.hourlyRate || "150";
                callRateInput.value = button.dataset.callRate || "3";
                bonusInput.value = button.dataset.bonus || "500";
                isActiveInput.checked = button.dataset.isActive === "true";
                titleNode.textContent = "Edit Staff Member";
                modal.show();
            });
        });

        document.querySelectorAll(".js-delete-staff").forEach((button) => {
            button.addEventListener("click", async () => {
                const staffId = button.dataset.staffId;
                const staffName = button.dataset.name || "this staff member";
                const confirmed = await confirmAction(`Delete ${staffName}?`, {
                    title: "Delete staff",
                    confirmText: "Delete",
                });
                if (!staffId || !confirmed) {
                    return;
                }
                try {
                    await requestJson(`${config.teamMembersUrl}${staffId}/`, { method: "DELETE" });
                    window.location.reload();
                } catch (error) {
                    window.alert(error.message);
                }
            });
        });

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            clearFeedback();
            submitButton.disabled = true;

            const staffId = idInput.value.trim();
            const payload = {
                name: nameInput.value.trim(),
                phone: phoneInput.value.trim(),
                hourly_rate: hourlyRateInput.value || "150",
                call_rate: callRateInput.value || "3",
                bonus_per_conversion: bonusInput.value || "500",
                is_active: isActiveInput.checked,
            };
            if (passwordInput.value.trim()) {
                payload.password = passwordInput.value.trim();
            }

            try {
                const url = staffId ? `${config.teamMembersUrl}${staffId}/` : config.teamMembersUrl;
                const method = staffId ? "PATCH" : "POST";
                await requestJson(url, {
                    method,
                    body: JSON.stringify(payload),
                });
                showFeedback("Staff saved successfully.", false);
                window.setTimeout(() => window.location.reload(), 500);
            } catch (error) {
                showFeedback(error.message, true);
            } finally {
                submitButton.disabled = false;
            }
        });
    }

    function bindLeadCrud() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("leadModal");
        const form = document.getElementById("leadForm");
        if (!config?.leadsUrl || !modalNode || !form) {
            return;
        }

        const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
        const titleNode = document.getElementById("leadModalTitle");
        const idInput = document.getElementById("leadFormId");
        const nameInput = document.getElementById("leadName");
        const phoneInput = document.getElementById("leadPhone");
        const statusInput = document.getElementById("leadStatus");
        const callbackWindowInput = document.getElementById("leadCallbackWindow");
        const callbackDateInput = document.getElementById("leadCallbackDate");
        const assignedToInput = document.getElementById("leadAssignedTo");
        const notesInput = document.getElementById("leadNotes");
        const feedback = document.getElementById("leadFormFeedback");
        const submitButton = document.getElementById("leadSubmitButton");
        const openSelectionButtons = Array.from(document.querySelectorAll(".js-open-lead-selection-mode"));
        const openAllocationButtons = Array.from(document.querySelectorAll(".js-open-lead-allocation-mode"));
        const deleteSelectedButtons = Array.from(document.querySelectorAll(".js-delete-selected-leads-button"));
        const allocateSelectedButtons = Array.from(document.querySelectorAll(".js-allocate-selected-leads-button"));
        const bulkDeleteForm = document.getElementById("bulkLeadDeleteForm");
        const bulkDeleteInputs = document.getElementById("bulkLeadDeleteInputs");
        const bulkAllocateModalNode = document.getElementById("bulkLeadAllocateModal");
        const bulkAllocateModal = bulkAllocateModalNode
            ? bootstrap.Modal.getOrCreateInstance(bulkAllocateModalNode)
            : null;
        const bulkAllocateForm = document.getElementById("bulkLeadAllocateForm");
        const bulkAllocateInputs = document.getElementById("bulkLeadAllocateInputs");
        const bulkAllocateStaffInput = document.getElementById("bulkLeadAllocateStaff");
        const selectAllCheckbox = document.getElementById("leadSelectAll");
        const selectionColumns = Array.from(document.querySelectorAll(".lead-select-column"));
        const selectionCheckboxes = Array.from(document.querySelectorAll(".js-lead-select-checkbox"));
        let selectionMode = "";

        function showFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        function resetForm() {
            form.reset();
            idInput.value = "";
            statusInput.value = "new";
            callbackWindowInput.value = "";
            callbackDateInput.value = "";
            assignedToInput.value = "";
            titleNode.textContent = "Add Lead";
            clearFeedback();
        }

        function refreshSelectionActionState() {
            const selectedCount = selectionCheckboxes.filter((checkbox) => checkbox.checked).length;
            deleteSelectedButtons.forEach((button) => {
                button.disabled = selectedCount === 0;
                button.textContent = selectedCount > 0 ? `Delete Marked (${selectedCount})` : "Delete Marked";
            });
            allocateSelectedButtons.forEach((button) => {
                button.disabled = selectedCount === 0;
                button.textContent = selectedCount > 0 ? `Allocate Marked (${selectedCount})` : "Allocate Marked";
            });
            if (selectAllCheckbox) {
                selectAllCheckbox.checked = selectedCount > 0 && selectedCount === selectionCheckboxes.length;
                selectAllCheckbox.indeterminate = selectedCount > 0 && selectedCount < selectionCheckboxes.length;
            }
        }

        function clearLeadSelections() {
            selectionCheckboxes.forEach((checkbox) => {
                checkbox.checked = false;
            });
            if (selectAllCheckbox) {
                selectAllCheckbox.checked = false;
                selectAllCheckbox.indeterminate = false;
            }
        }

        function toggleSelectionMode(nextMode) {
            const mode = nextMode || "";
            const enabled = Boolean(mode);
            const changedMode = selectionMode !== mode;
            selectionMode = mode;
            selectionColumns.forEach((node) => node.classList.toggle("d-none", !enabled));
            deleteSelectedButtons.forEach((button) => {
                button.classList.toggle("d-none", mode !== "delete");
            });
            allocateSelectedButtons.forEach((button) => {
                button.classList.toggle("d-none", mode !== "allocate");
            });
            openSelectionButtons.forEach((button) => {
                const isDeleteMode = mode === "delete";
                button.textContent = isDeleteMode ? "Cancel Delete" : "Delete Leads";
                button.classList.toggle("btn-outline-danger", !isDeleteMode);
                button.classList.toggle("btn-outline-secondary", isDeleteMode);
            });
            openAllocationButtons.forEach((button) => {
                const isAllocateMode = mode === "allocate";
                button.textContent = isAllocateMode ? "Cancel Allocation" : "Allocate Leads";
                button.classList.toggle("btn-outline-success", !isAllocateMode);
                button.classList.toggle("btn-outline-secondary", isAllocateMode);
            });
            if (!enabled || changedMode) {
                clearLeadSelections();
            }
            refreshSelectionActionState();
        }

        statusInput.addEventListener("change", () => {
            if (statusInput.value !== "call_back") {
                callbackWindowInput.value = "";
                callbackDateInput.value = "";
            }
        });

        document.getElementById("openCreateLeadModal")?.addEventListener("click", resetForm);
        modalNode.addEventListener("hidden.bs.modal", clearFeedback);

        openSelectionButtons.forEach((button) => {
            button.addEventListener("click", () => {
                toggleSelectionMode(selectionMode === "delete" ? "" : "delete");
            });
        });

        openAllocationButtons.forEach((button) => {
            button.addEventListener("click", () => {
                toggleSelectionMode(selectionMode === "allocate" ? "" : "allocate");
            });
        });

        selectAllCheckbox?.addEventListener("change", () => {
            selectionCheckboxes.forEach((checkbox) => {
                checkbox.checked = selectAllCheckbox.checked;
            });
            refreshSelectionActionState();
        });

        selectionCheckboxes.forEach((checkbox) => {
            checkbox.addEventListener("change", refreshSelectionActionState);
        });

        deleteSelectedButtons.forEach((button) => {
            button.addEventListener("click", async () => {
                const selectedIds = selectionCheckboxes
                    .filter((checkbox) => checkbox.checked)
                    .map((checkbox) => checkbox.value);
                if (!selectedIds.length) {
                    window.alert("Select at least one lead to delete.");
                    return;
                }
                if (!bulkDeleteForm || !bulkDeleteInputs) {
                    return;
                }
                const confirmed = await confirmAction(`Delete ${selectedIds.length} selected lead(s)?`, {
                    title: "Delete leads",
                    confirmText: "Delete",
                });
                if (!confirmed) {
                    return;
                }
                bulkDeleteInputs.innerHTML = "";
                selectedIds.forEach((leadId) => {
                    const input = document.createElement("input");
                    input.type = "hidden";
                    input.name = "selected_lead_ids";
                    input.value = leadId;
                    bulkDeleteInputs.appendChild(input);
                });
                bulkDeleteForm.submit();
            });
        });

        allocateSelectedButtons.forEach((button) => {
            button.addEventListener("click", () => {
                const selectedIds = selectionCheckboxes
                    .filter((checkbox) => checkbox.checked)
                    .map((checkbox) => checkbox.value);
                if (!selectedIds.length) {
                    window.alert("Select at least one lead to allocate.");
                    return;
                }
                if (!bulkAllocateModal) {
                    return;
                }
                if (bulkAllocateStaffInput) {
                    bulkAllocateStaffInput.value = "";
                }
                bulkAllocateModal.show();
            });
        });

        bulkAllocateForm?.addEventListener("submit", (event) => {
            const selectedIds = selectionCheckboxes
                .filter((checkbox) => checkbox.checked)
                .map((checkbox) => checkbox.value);
            if (!selectedIds.length) {
                event.preventDefault();
                window.alert("Select at least one lead to allocate.");
                return;
            }
            if (!bulkAllocateInputs || !bulkAllocateStaffInput?.value) {
                event.preventDefault();
                window.alert("Choose the staff member who should receive these leads.");
                return;
            }

            bulkAllocateInputs.innerHTML = "";
            selectedIds.forEach((leadId) => {
                const input = document.createElement("input");
                input.type = "hidden";
                input.name = "selected_lead_ids";
                input.value = leadId;
                bulkAllocateInputs.appendChild(input);
            });
        });

        document.querySelectorAll(".js-edit-lead").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback();
                idInput.value = button.dataset.leadId || "";
                nameInput.value = button.dataset.name || "";
                phoneInput.value = button.dataset.phone || "";
                statusInput.value = button.dataset.status || "new";
                callbackWindowInput.value = button.dataset.callbackWindow || "";
                callbackDateInput.value = button.dataset.callbackDate || "";
                assignedToInput.value = button.dataset.assignedToId || "";
                notesInput.value = button.dataset.notes || "";
                titleNode.textContent = "Edit Lead";
                modal.show();
            });
        });

        document.querySelectorAll(".js-delete-lead").forEach((button) => {
            button.addEventListener("click", async () => {
                const leadId = button.dataset.leadId;
                const leadName = button.dataset.name || "this lead";
                const confirmed = await confirmAction(`Delete ${leadName}?`, {
                    title: "Delete lead",
                    confirmText: "Delete",
                });
                if (!leadId || !confirmed) {
                    return;
                }
                try {
                    await requestJson(`${config.leadsUrl}${leadId}/`, { method: "DELETE" });
                    window.location.reload();
                } catch (error) {
                    window.alert(error.message);
                }
            });
        });

        refreshSelectionActionState();

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            clearFeedback();
            submitButton.disabled = true;

            const leadId = idInput.value.trim();
            const payload = {
                name: nameInput.value.trim(),
                phone: phoneInput.value.trim(),
                status: statusInput.value,
                callback_window: callbackWindowInput.value || "",
                callback_date: callbackDateInput.value || null,
                assigned_to: assignedToInput.value || null,
                notes: notesInput.value.trim(),
            };

            try {
                const url = leadId ? `${config.leadsUrl}${leadId}/` : config.leadsUrl;
                const method = leadId ? "PATCH" : "POST";
                await requestJson(url, {
                    method,
                    body: JSON.stringify(payload),
                });
                showFeedback("Lead saved successfully.", false);
                window.setTimeout(() => window.location.reload(), 500);
            } catch (error) {
                showFeedback(error.message, true);
            } finally {
                submitButton.disabled = false;
            }
        });
    }

    function bindHandoverUpdates() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("handoverModal");
        if (!config?.leadsUrl || !modalNode) {
            return;
        }

        const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
        const titleNode = document.getElementById("handoverModalTitle");
        const form = document.getElementById("handoverForm");
        const leadIdInput = document.getElementById("handoverLeadId");
        const statusInput = document.getElementById("handoverStatus");
        const feedback = document.getElementById("handoverFormFeedback");
        const submitButton = document.getElementById("handoverSubmitButton");

        function showFeedback(message, isError) {
            if (!feedback) {
                return;
            }
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            if (!feedback) {
                return;
            }
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        document.querySelectorAll(".js-edit-handover").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback();
                if (leadIdInput) {
                    leadIdInput.value = button.dataset.leadId || "";
                }
                if (statusInput) {
                    statusInput.value = button.dataset.handoverStatus || "not_sent";
                }
                if (titleNode) {
                    titleNode.textContent = `Update Handover - ${button.dataset.leadName || "Lead"}`;
                }
                modal.show();
            });
        });

        if (form) {
            form.addEventListener("submit", async (event) => {
                event.preventDefault();
                clearFeedback();
                if (!leadIdInput?.value) {
                    showFeedback("Select a lead before saving.", true);
                    return;
                }
                if (submitButton) {
                    submitButton.disabled = true;
                }
                try {
                    await requestJson(`${config.leadsUrl}${leadIdInput.value}/`, {
                        method: "PATCH",
                        body: JSON.stringify({
                            handover_status: statusInput?.value || "not_sent",
                        }),
                    });
                    showFeedback("Handover status updated.", false);
                    window.setTimeout(() => window.location.reload(), 400);
                } catch (error) {
                    showFeedback(error.message, true);
                } finally {
                    if (submitButton) {
                        submitButton.disabled = false;
                    }
                }
            });
        }
    }

    function bindLeadImport() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("leadImportModal");
        const form = document.getElementById("leadImportForm");
        if (!config?.leadImportUrl || !modalNode || !form) {
            return;
        }

        const fileInput = document.getElementById("leadImportFile");
        const assignmentModeInputs = Array.from(
            form.querySelectorAll('input[name="assignment_mode"]'),
        );
        const feedback = document.getElementById("leadImportFeedback");
        const submitButton = document.getElementById("leadImportSubmitButton");

        function showFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        function resetForm() {
            form.reset();
            clearFeedback();
        }

        document.getElementById("openLeadImportModal")?.addEventListener("click", resetForm);
        modalNode.addEventListener("hidden.bs.modal", clearFeedback);

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            clearFeedback();

            const file = fileInput?.files?.[0];
            if (!file) {
                showFeedback("Choose a CSV, Excel, or VCF file to continue.", true);
                return;
            }

            submitButton.disabled = true;
            const formData = new FormData();
            formData.append("file", file);
            const selectedAssignmentMode =
                assignmentModeInputs.find((input) => input.checked)?.value || "auto";
            formData.append("assignment_mode", selectedAssignmentMode);
            if (selectedAssignmentMode === "selected_staff") {
                Array.from(
                    form.querySelectorAll('input[name="assigned_staff_ids"]:checked'),
                ).forEach((input) => {
                    formData.append("assigned_staff_ids", input.value);
                });
            }

            try {
                const result = await requestForm(config.leadImportUrl, formData, { method: "POST" });
                const assignmentNote =
                    result.assignment_mode === "selected_staff"
                        ? ` Loaded into ${result.selected_staff_count} selected staff queue(s).`
                        : "";
                const successMessage = `Imported ${result.created_count} leads, skipped ${result.skipped_count}, assigned ${result.assigned_count}, waiting ${result.remaining_unassigned_count}.${assignmentNote}`;
                showFeedback(successMessage, false);
                storeFlashMessage(successMessage, "success");
                window.setTimeout(() => window.location.reload(), 900);
            } catch (error) {
                showFeedback(error.message, true);
            } finally {
                submitButton.disabled = false;
            }
        });
    }

    function bindTrainingCrud() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("trainingModal");
        const form = document.getElementById("trainingForm");
        if (!config?.trainingUrl || !modalNode || !form) {
            return;
        }

        const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
        const titleNode = document.getElementById("trainingModalTitle");
        const idInput = document.getElementById("trainingFormId");
        const lessonTitleInput = document.getElementById("trainingTitle");
        const descriptionInput = document.getElementById("trainingDescription");
        const videoUrlInput = document.getElementById("trainingVideoUrl");
        const keywordsInput = document.getElementById("trainingKeywords");
        const sortOrderInput = document.getElementById("trainingSortOrder");
        const mandatoryInput = document.getElementById("trainingIsMandatory");
        const activeInput = document.getElementById("trainingIsActive");
        const feedback = document.getElementById("trainingFormFeedback");
        const submitButton = document.getElementById("trainingSubmitButton");

        function showFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        function resetForm() {
            form.reset();
            idInput.value = "";
            sortOrderInput.value = "0";
            mandatoryInput.checked = true;
            activeInput.checked = true;
            titleNode.textContent = "Add Lesson";
            clearFeedback();
        }

        document.getElementById("openCreateTrainingModal")?.addEventListener("click", resetForm);
        modalNode.addEventListener("hidden.bs.modal", clearFeedback);

        document.querySelectorAll(".js-edit-training").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback();
                idInput.value = button.dataset.lessonId || "";
                lessonTitleInput.value = button.dataset.title || "";
                descriptionInput.value = button.dataset.description || "";
                videoUrlInput.value = button.dataset.videoUrl || "";
                keywordsInput.value = button.dataset.searchKeywords || "";
                sortOrderInput.value = button.dataset.sortOrder || "0";
                mandatoryInput.checked = button.dataset.isMandatory === "true";
                activeInput.checked = button.dataset.isActive === "true";
                titleNode.textContent = "Edit Lesson";
                modal.show();
            });
        });

        document.querySelectorAll(".js-delete-training").forEach((button) => {
            button.addEventListener("click", async () => {
                const lessonId = button.dataset.lessonId;
                const lessonTitle = button.dataset.title || "this lesson";
                const confirmed = await confirmAction(`Delete ${lessonTitle}?`, {
                    title: "Delete lesson",
                    confirmText: "Delete",
                });
                if (!lessonId || !confirmed) {
                    return;
                }
                try {
                    await requestJson(`${config.trainingUrl}${lessonId}/`, { method: "DELETE" });
                    window.location.reload();
                } catch (error) {
                    window.alert(error.message);
                }
            });
        });

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            clearFeedback();
            submitButton.disabled = true;

            const lessonId = idInput.value.trim();
            const payload = {
                title: lessonTitleInput.value.trim(),
                description: descriptionInput.value.trim(),
                video_url: videoUrlInput.value.trim(),
                search_keywords: keywordsInput.value.trim(),
                sort_order: Number(sortOrderInput.value || "0"),
                is_mandatory: mandatoryInput.checked,
                is_active: activeInput.checked,
            };

            try {
                const url = lessonId ? `${config.trainingUrl}${lessonId}/` : config.trainingUrl;
                const method = lessonId ? "PATCH" : "POST";
                await requestJson(url, {
                    method,
                    body: JSON.stringify(payload),
                });
                showFeedback("Lesson saved successfully.", false);
                window.setTimeout(() => window.location.reload(), 500);
            } catch (error) {
                showFeedback(error.message, true);
            } finally {
                submitButton.disabled = false;
            }
        });
    }

    function bindFollowupConversion() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("followupConvertModal");
        const confirmButton = document.getElementById("followupConvertConfirm");
        if (!config?.leadsUrl || !modalNode || !confirmButton) {
            return;
        }

        const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
        const titleNode = document.getElementById("followupConvertTitle");
        const messageNode = document.getElementById("followupConvertMessage");
        const feedback = document.getElementById("followupConvertFeedback");
        let activeLeadId = "";

        function showFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        document.querySelectorAll(".js-mark-converted").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback();
                activeLeadId = button.dataset.leadId || "";
                const leadName = button.dataset.leadName || "this lead";
                titleNode.textContent = "Mark as Converted";
                messageNode.textContent = `Confirm ${leadName} as converted? This removes it from the follow-up queue.`;
                modal.show();
            });
        });

        confirmButton.addEventListener("click", async () => {
            if (!activeLeadId) {
                return;
            }
            confirmButton.disabled = true;
            clearFeedback();
            try {
                await requestJson(`${config.leadsUrl}${activeLeadId}/`, {
                    method: "PATCH",
                    body: JSON.stringify({ status: "converted" }),
                });
                showFeedback("Lead marked as converted.", false);
                window.setTimeout(() => window.location.reload(), 600);
            } catch (error) {
                showFeedback(error.message, true);
            } finally {
                confirmButton.disabled = false;
            }
        });
    }

    function bindInterestedLeadDecisions() {
        const config = window.heavenectionAdmin;
        if (!config?.leadsUrl) {
            return;
        }

        const successModalNode = document.getElementById("interestedSuccessModal");
        const successConfirmButton = document.getElementById("interestedSuccessConfirm");
        const successTitleNode = document.getElementById("interestedSuccessTitle");
        const successMessageNode = document.getElementById("interestedSuccessMessage");
        const successFeedback = document.getElementById("interestedSuccessFeedback");
        const unsuccessfulModalNode = document.getElementById("interestedUnsuccessfulModal");
        const unsuccessfulForm = document.getElementById("interestedUnsuccessfulForm");
        const unsuccessfulLeadIdInput = document.getElementById("interestedUnsuccessfulLeadId");
        const unsuccessfulStatusInput = document.getElementById("interestedUnsuccessfulStatus");
        const unsuccessfulTitleNode = document.getElementById("interestedUnsuccessfulTitle");
        const unsuccessfulFeedback = document.getElementById("interestedUnsuccessfulFeedback");
        const unsuccessfulSubmitButton = document.getElementById("interestedUnsuccessfulSubmit");

        const successModal = successModalNode
            ? bootstrap.Modal.getOrCreateInstance(successModalNode)
            : null;
        const unsuccessfulModal = unsuccessfulModalNode
            ? bootstrap.Modal.getOrCreateInstance(unsuccessfulModalNode)
            : null;
        let activeLeadId = "";

        function showFeedback(node, message, isError) {
            if (!node) {
                return;
            }
            node.textContent = message;
            node.classList.remove("d-none", "is-success", "is-error");
            node.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback(node) {
            if (!node) {
                return;
            }
            node.textContent = "";
            node.classList.add("d-none");
            node.classList.remove("is-success", "is-error");
        }

        document.querySelectorAll(".js-interested-success").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback(successFeedback);
                activeLeadId = button.dataset.leadId || "";
                const leadName = button.dataset.leadName || "this lead";
                if (successTitleNode) {
                    successTitleNode.textContent = "Mark Successful";
                }
                if (successMessageNode) {
                    successMessageNode.textContent = `Confirm ${leadName} as successful? This will move the lead to Converted.`;
                }
                successModal?.show();
            });
        });

        if (successConfirmButton) {
            successConfirmButton.addEventListener("click", async () => {
                if (!activeLeadId) {
                    return;
                }
                clearFeedback(successFeedback);
                successConfirmButton.disabled = true;
                try {
                    await requestJson(`${config.leadsUrl}${activeLeadId}/`, {
                        method: "PATCH",
                        body: JSON.stringify({ status: "converted" }),
                    });
                    showFeedback(successFeedback, "Lead marked as successful.", false);
                    window.setTimeout(() => window.location.reload(), 500);
                } catch (error) {
                    showFeedback(successFeedback, error.message, true);
                } finally {
                    successConfirmButton.disabled = false;
                }
            });
        }

        document.querySelectorAll(".js-interested-unsuccessful").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback(unsuccessfulFeedback);
                if (unsuccessfulLeadIdInput) {
                    unsuccessfulLeadIdInput.value = button.dataset.leadId || "";
                }
                if (unsuccessfulStatusInput) {
                    unsuccessfulStatusInput.value = button.dataset.currentStatus || "interested";
                    if (!["interested", "not_interested", "no_answer"].includes(unsuccessfulStatusInput.value)) {
                        unsuccessfulStatusInput.value = "interested";
                    }
                }
                if (unsuccessfulTitleNode) {
                    unsuccessfulTitleNode.textContent = `Mark Unsuccessful - ${button.dataset.leadName || "Lead"}`;
                }
                unsuccessfulModal?.show();
            });
        });

        if (unsuccessfulForm) {
            unsuccessfulForm.addEventListener("submit", async (event) => {
                event.preventDefault();
                clearFeedback(unsuccessfulFeedback);
                const leadId = unsuccessfulLeadIdInput?.value || "";
                const targetStatus = unsuccessfulStatusInput?.value || "interested";
                if (!leadId) {
                    showFeedback(unsuccessfulFeedback, "Select a lead before saving.", true);
                    return;
                }
                if (unsuccessfulSubmitButton) {
                    unsuccessfulSubmitButton.disabled = true;
                }
                try {
                    await requestJson(`${config.leadsUrl}${leadId}/`, {
                        method: "PATCH",
                        body: JSON.stringify({ status: targetStatus }),
                    });
                    showFeedback(unsuccessfulFeedback, "Lead updated successfully.", false);
                    window.setTimeout(() => window.location.reload(), 500);
                } catch (error) {
                    showFeedback(unsuccessfulFeedback, error.message, true);
                } finally {
                    if (unsuccessfulSubmitButton) {
                        unsuccessfulSubmitButton.disabled = false;
                    }
                }
            });
        }
    }

    function bindSalaryControlCrud() {
        const config = window.heavenectionAdmin;
        const modalNode = document.getElementById("salaryControlModal");
        const form = document.getElementById("salaryControlForm");
        if (!config?.salaryControlUrl || !modalNode || !form) {
            return;
        }

        const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
        const titleNode = document.getElementById("salaryControlModalTitle");
        const idInput = document.getElementById("salaryControlStaffId");
        const nameInput = document.getElementById("salaryControlStaffName");
        const phoneInput = document.getElementById("salaryControlPhone");
        const emailInput = document.getElementById("salaryControlEmail");
        const compensationTypeInput = document.getElementById("salaryCompensationType");
        const hourlyRateInput = document.getElementById("salaryHourlyRate");
        const weeklyPayoutDayInput = document.getElementById("salaryWeeklyPayoutDay");
        const targetWeekInput = document.getElementById("salaryTargetHoursWeek");
        const targetMonthInput = document.getElementById("salaryTargetHoursMonth");
        const callRateInput = document.getElementById("salaryCallRate");
        const bonusRateInput = document.getElementById("salaryBonusRate");
        const referredByInput = document.getElementById("salaryReferredBy");
        const accountHolderValue = document.getElementById("salaryControlAccountHolderValue");
        const bankNameValue = document.getElementById("salaryControlBankNameValue");
        const accountNumberValue = document.getElementById("salaryControlAccountNumberValue");
        const ifscValue = document.getElementById("salaryControlIfscValue");
        const passbookLink = document.getElementById("salaryControlPassbookLink");
        const passbookPreview = document.getElementById("salaryControlPassbookPreview");
        const passbookImage = document.getElementById("salaryControlPassbookImage");
        const passbookEmpty = document.getElementById("salaryControlPassbookEmpty");
        const profileLink = document.getElementById("salaryControlProfileLink");
        const feedback = document.getElementById("salaryControlFeedback");
        const submitButton = document.getElementById("salaryControlSubmit");

        function setText(node, value, fallback = "Not added yet") {
            if (!node) {
                return;
            }
            const resolved = (value || "").toString().trim();
            node.textContent = resolved || fallback;
        }

        function showFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        modalNode.addEventListener("hidden.bs.modal", clearFeedback);

        document.querySelectorAll(".js-edit-salary").forEach((button) => {
            button.addEventListener("click", () => {
                clearFeedback();
                idInput.value = button.dataset.staffId || "";
                nameInput.value = button.dataset.name || "";
                phoneInput.value = button.dataset.phone || "";
                if (emailInput) {
                    emailInput.value = button.dataset.email || "";
                }
                compensationTypeInput.value = button.dataset.compensationType || "hourly";
                hourlyRateInput.value = button.dataset.hourlyRate || "150";
                if (weeklyPayoutDayInput) {
                    weeklyPayoutDayInput.value = button.dataset.weeklyPayoutDay || "wednesday";
                }
                targetWeekInput.value = button.dataset.targetHoursWeek || "48";
                targetMonthInput.value = button.dataset.targetHoursMonth || "208";
                callRateInput.value = button.dataset.callRate || "3";
                bonusRateInput.value = button.dataset.bonus || "10";
                if (referredByInput) {
                    referredByInput.value = button.dataset.referredById || "";
                }
                setText(accountHolderValue, button.dataset.bankAccountName);
                setText(bankNameValue, button.dataset.bankName);
                setText(accountNumberValue, button.dataset.bankAccountNumber);
                setText(ifscValue, button.dataset.bankIfsc);
                const passbookUrl = button.dataset.passbookPhotoUrl || "";
                if (passbookLink) {
                    passbookLink.hidden = !passbookUrl;
                    passbookLink.href = passbookUrl || "#";
                }
                if (passbookPreview) {
                    passbookPreview.hidden = !passbookUrl;
                }
                if (passbookImage && passbookUrl) {
                    passbookImage.src = passbookUrl;
                } else if (passbookImage) {
                    passbookImage.removeAttribute("src");
                }
                if (passbookEmpty) {
                    passbookEmpty.hidden = Boolean(passbookUrl);
                }
                if (profileLink) {
                    const resolvedProfileUrl = button.dataset.profileUrl || "";
                    profileLink.hidden = !resolvedProfileUrl;
                    profileLink.href = resolvedProfileUrl || "#";
                }
                titleNode.textContent = `Salary Settings - ${button.dataset.name || "Staff"}`;
                modal.show();
            });
        });

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            clearFeedback();
            submitButton.disabled = true;

            const staffId = idInput.value.trim();
            if (!staffId) {
                showFeedback("Staff member could not be identified.", true);
                submitButton.disabled = false;
                return;
            }

            const payload = {
                compensation_type: compensationTypeInput.value,
                hourly_rate: hourlyRateInput.value || "0",
                weekly_payout_day: weeklyPayoutDayInput?.value || "wednesday",
                target_hours_per_week: targetWeekInput.value || "48",
                target_hours_per_month: targetMonthInput.value || "208",
                call_rate: callRateInput.value || "0",
                bonus_per_conversion: bonusRateInput.value || "0",
                referred_by_id: referredByInput?.value || null,
            };

            try {
                await requestJson(`${config.salaryControlUrl}${staffId}/`, {
                    method: "PATCH",
                    body: JSON.stringify(payload),
                });
                showFeedback("Salary settings saved successfully.", false);
                window.setTimeout(() => window.location.reload(), 500);
            } catch (error) {
                showFeedback(error.message, true);
            } finally {
                submitButton.disabled = false;
            }
        });
    }

    function bindLiveMonitoringPage() {
        const root = document.getElementById("heavenectionLiveMonitoringPage");
        if (!root) {
            return;
        }

        const apiUrl = root.dataset.apiUrl || window.heavenectionAdmin?.liveMonitoringUrl;
        const summaryGrid = document.getElementById("liveMonitoringSummaryGrid");
        const activeGrid = document.getElementById("liveMonitoringActiveGrid");
        const alertGrid = document.getElementById("liveMonitoringAlertGrid");
        const spotlightGrid = document.getElementById("liveMonitoringSpotlightGrid");
        const staffGrid = document.getElementById("liveMonitoringStaffGrid");
        const generatedAtNode = document.getElementById("liveMonitoringGeneratedAt");
        const refreshButton = document.getElementById("liveMonitoringRefreshButton");
        let refreshInFlight = false;

        function asNumber(value) {
            const number = Number(value || 0);
            return Number.isFinite(number) ? number : 0;
        }

        function renderSummary(summary) {
            if (!summaryGrid || !summary) {
                return;
            }
            const awayOffline = asNumber(summary.away_now) + asNumber(summary.offline_now);
            summaryGrid.innerHTML = `
                <article class="hc-live-command-card">
                    <span class="hc-live-command-label">Ready In App</span>
                    <strong>${asNumber(summary.online_now)}</strong>
                    <small>${asNumber(summary.active_accounts)} active accounts today</small>
                </article>
                <article class="hc-live-command-card">
                    <span class="hc-live-command-label">On Live Calls</span>
                    <strong>${asNumber(summary.on_call_now)}</strong>
                    <small>${asNumber(summary.total_calls_today)} calls recorded today</small>
                </article>
                <article class="hc-live-command-card">
                    <span class="hc-live-command-label">Queue Pressure</span>
                    <strong>${asNumber(summary.total_assigned)}</strong>
                    <small>Assigned leads currently waiting</small>
                </article>
                <article class="hc-live-command-card">
                    <span class="hc-live-command-label">Review Signals</span>
                    <strong>${asNumber(summary.review_needed_now)}</strong>
                    <small>${asNumber(summary.alert_now)} more alerts need attention</small>
                </article>
                <article class="hc-live-command-card">
                    <span class="hc-live-command-label">Active Work</span>
                    <strong>${escapeHtml(summary.active_hours_label || "0.0h")}</strong>
                    <small>${asNumber(summary.total_converted_today)} successful leads today</small>
                </article>
                <article class="hc-live-command-card">
                    <span class="hc-live-command-label">Away Or Offline</span>
                    <strong>${awayOffline}</strong>
                    <small>${asNumber(summary.away_now)} away and ${asNumber(summary.offline_now)} offline</small>
                </article>
            `;
        }

        function renderActiveGrid(rows) {
            if (!activeGrid) {
                return;
            }
            const activeRows = (Array.isArray(rows) ? rows : []).filter((row) => row?.is_on_call || row?.online_label === "Online");
            if (!activeRows.length) {
                activeGrid.innerHTML = '<div class="hc-work-review-empty-note">No active staff are visible right now.</div>';
                return;
            }
            activeGrid.innerHTML = activeRows.map((row) => `
                <article class="hc-live-monitor-card hc-live-activity-card">
                    <div class="d-flex align-items-start justify-content-between gap-3">
                        <div class="hc-staff-persona">
                            <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                            <div class="hc-staff-persona-copy">
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <span>${escapeHtml(row.phone || "--")}</span>
                                <small>${escapeHtml(row.session_state_label || "Unavailable")}</small>
                            </div>
                        </div>
                        <span class="hc-status hc-status-${escapeHtml(row.status_tone || "muted")}">${escapeHtml(row.online_label || "Offline")}</span>
                    </div>
                    <div class="hc-live-monitor-note mt-3">${escapeHtml(row.status_note || "")}</div>
                    <div class="hc-live-monitor-metrics mt-3">
                        <span>${escapeHtml(row.active_hours_today || "0.0h")} worked</span>
                        <span>${asNumber(row.calls_today)} calls</span>
                        <span>${asNumber(row.assigned_leads)} queue</span>
                        <span>${escapeHtml(row.last_seen || "--")}</span>
                    </div>
                    ${row.current_call ? `
                        <div class="hc-live-monitor-call mt-3">
                            <strong>${escapeHtml(row.current_call.lead_name || "Lead")}</strong>
                            <span>${escapeHtml(row.current_call.lead_phone || "--")}</span>
                            <small>${escapeHtml(row.current_call.duration_label || "--")} live call</small>
                        </div>
                    ` : '<div class="hc-live-staff-empty mt-3">Ready in the app and available for the next customer call.</div>'}
                </article>
            `).join("");
        }

        function renderAlertGrid(rows) {
            if (!alertGrid) {
                return;
            }
            const alertRows = (Array.isArray(rows) ? rows : []).filter((row) => (
                row?.quality_label === "Review Needed"
                || row?.quality_label === "Needs Attention"
                || row?.online_label === "Away"
                || row?.online_label === "Warning"
            ));
            if (!alertRows.length) {
                alertGrid.innerHTML = '<div class="hc-work-review-empty-note">No live review alerts are visible right now.</div>';
                return;
            }
            alertGrid.innerHTML = alertRows.map((row) => `
                <article class="hc-live-monitor-card hc-live-alert-card">
                    <div class="d-flex align-items-start justify-content-between gap-3">
                        <div class="hc-staff-persona">
                            <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                            <div class="hc-staff-persona-copy">
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <span>${escapeHtml(row.phone || "--")}</span>
                                <small>${escapeHtml(row.compensation_type_label || "Hourly")}</small>
                            </div>
                        </div>
                        <span class="hc-status hc-status-${escapeHtml(row.quality_tone || "muted")}">${escapeHtml(row.quality_label || "Attention")}</span>
                    </div>
                    <div class="hc-live-monitor-note mt-3">${escapeHtml(row.quality_note || row.status_note || "")}</div>
                    <div class="hc-live-monitor-metrics mt-3">
                        <span>${asNumber(row.gap_count)} gaps</span>
                        <span>${escapeHtml(row.gap_uncounted_label || "0s")} uncounted</span>
                        <span>${asNumber(row.zero_only_block_count)} zero-talk blocks</span>
                    </div>
                    <div class="hc-live-caption mt-3">
                        ${escapeHtml(row.attempt_review_label || "--")}. ${asNumber(row.real_call_count)} real calls, ${asNumber(row.zero_second_attempt_count)} zero-second, ${asNumber(row.invalid_short_count)} invalid short.
                    </div>
                </article>
            `).join("");
        }

        function renderSpotlight(rows) {
            if (!spotlightGrid) {
                return;
            }
            if (!Array.isArray(rows) || !rows.length) {
                spotlightGrid.innerHTML = '<div class="hc-work-review-empty-note">No live staff activity is available right now.</div>';
                return;
            }

            spotlightGrid.innerHTML = rows.map((row) => `
                <article class="hc-live-monitor-card">
                    <div class="d-flex align-items-start justify-content-between gap-3">
                        <div class="hc-staff-persona">
                            <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                            <div class="hc-staff-persona-copy">
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <span>${escapeHtml(row.phone || "--")}</span>
                                <small>${escapeHtml(row.compensation_type_label || "Hourly")}</small>
                            </div>
                        </div>
                        <span class="hc-status hc-status-${escapeHtml(row.status_tone || "muted")}">${escapeHtml(row.online_label || "Offline")}</span>
                    </div>
                    <div class="hc-live-monitor-note mt-3">${escapeHtml(row.status_note || "")}</div>
                    <div class="hc-live-monitor-metrics mt-3">
                        <span>${escapeHtml(row.active_hours_today || "0.0h")} worked</span>
                        <span>${Number(row.calls_today || 0)} calls</span>
                        <span>${Number(row.assigned_leads || 0)} queue</span>
                    </div>
                    ${row.current_call ? `
                        <div class="hc-live-monitor-call mt-3">
                            <strong>${escapeHtml(row.current_call.lead_name || "Lead")}</strong>
                            <span>${escapeHtml(row.current_call.lead_phone || "--")}</span>
                            <small>${escapeHtml(row.current_call.duration_label || "--")} live call</small>
                        </div>
                    ` : ""}
                </article>
            `).join("");
        }

        function renderStaffGrid(rows) {
            if (!staffGrid) {
                return;
            }
            if (!Array.isArray(rows) || !rows.length) {
                staffGrid.innerHTML = '<div class="hc-work-review-empty-note">No live monitoring details are available right now.</div>';
                return;
            }

            staffGrid.innerHTML = rows.map((row) => `
                <article class="hc-live-staff-card">
                    <div class="d-flex align-items-start justify-content-between gap-3">
                        <div class="hc-staff-persona">
                            <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                            <div class="hc-staff-persona-copy">
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <span>${escapeHtml(row.phone || "--")}</span>
                                <small>${escapeHtml(row.compensation_type_label || "Hourly")}</small>
                            </div>
                        </div>
                        <span class="hc-status hc-status-${escapeHtml(row.status_tone || "muted")}">${escapeHtml(row.online_label || "Offline")}</span>
                    </div>

                    <div class="hc-live-staff-meta">
                        <div>
                            <span class="hc-live-mini-label">Session</span>
                            <strong>${escapeHtml(row.session_state_label || "Unavailable")}</strong>
                        </div>
                        <div>
                            <span class="hc-live-mini-label">Last Seen</span>
                            <strong>${escapeHtml(row.last_seen || "--")}</strong>
                        </div>
                    </div>

                    <p class="hc-live-staff-note">${escapeHtml(row.status_note || "")}</p>

                    ${row.current_call ? `
                        <div class="hc-live-monitor-call">
                            <strong>${escapeHtml(row.current_call.lead_name || "Lead")}</strong>
                            <span>${escapeHtml(row.current_call.lead_phone || "--")}</span>
                            <small>${escapeHtml(row.current_call.duration_label || "--")} live</small>
                        </div>
                    ` : '<div class="hc-live-staff-empty">No live customer call right now.</div>'}

                    <div class="hc-live-staff-columns">
                        <div class="hc-live-data-stack">
                            <span class="hc-live-mini-label">Today</span>
                            <div class="hc-live-pill-row">
                                <span class="hc-live-pill">${escapeHtml(row.active_hours_today || "0.0h")}</span>
                                <span class="hc-live-pill">${asNumber(row.calls_today)} calls</span>
                                <span class="hc-live-pill">${asNumber(row.converted_today)} success</span>
                                <span class="hc-live-pill">${asNumber(row.assigned_leads)} queue</span>
                                <span class="hc-live-pill">${escapeHtml(row.call_time_label || "0s")} call time</span>
                            </div>
                        </div>
                        <div class="hc-live-data-stack">
                            <span class="hc-live-mini-label">Review</span>
                            <div class="hc-quality-card-head">
                                <strong>${asNumber(row.quality_score)}</strong>
                                <span class="hc-status hc-status-${escapeHtml(row.quality_tone || "muted")}">${escapeHtml(row.quality_label || "No Recent Activity")}</span>
                            </div>
                            <div class="hc-live-caption">${escapeHtml(row.attempt_review_label || "--")}</div>
                            <div class="hc-live-caption">
                                ${asNumber(row.real_call_count)} real &middot; ${asNumber(row.zero_second_attempt_count)} zero-second &middot; ${asNumber(row.invalid_short_count)} invalid short
                            </div>
                        </div>
                        <div class="hc-live-data-stack">
                            <span class="hc-live-mini-label">Gaps And Review Blocks</span>
                            <div class="hc-live-pill-row">
                                <span class="hc-live-pill">${asNumber(row.gap_count)} gaps</span>
                                <span class="hc-live-pill">${escapeHtml(row.gap_uncounted_label || "0s")} uncounted</span>
                                <span class="hc-live-pill">${escapeHtml(row.away_review_label || "No long away periods")}</span>
                            </div>
                            <div class="hc-live-caption">
                                ${asNumber(row.suspicious_block_count)} review block(s) &middot; ${asNumber(row.zero_only_block_count)} zero-talk block(s)
                            </div>
                        </div>
                    </div>
                </article>
            `).join("");
        }

        function renderPayload(payload) {
            if (!payload || typeof payload !== "object") {
                return;
            }
            renderSummary(payload.summary || {});
            renderActiveGrid(payload.staff_rows || []);
            renderAlertGrid(payload.staff_rows || []);
            renderSpotlight(payload.spotlight_rows || []);
            renderStaffGrid(payload.staff_rows || []);
            if (generatedAtNode) {
                generatedAtNode.textContent = payload.generated_at_label || "--";
            }
        }

        async function refreshPayload() {
            if (!apiUrl || refreshInFlight) {
                return;
            }
            refreshInFlight = true;
            if (refreshButton) {
                refreshButton.disabled = true;
            }
            try {
                const payload = await requestJson(apiUrl, { method: "GET" });
                renderPayload(payload);
            } catch (error) {
                // Keep the last good render on screen.
            } finally {
                refreshInFlight = false;
                if (refreshButton) {
                    refreshButton.disabled = false;
                }
            }
        }

        renderPayload(readJsonScript("heavenectionLiveMonitoringPayload"));
        refreshButton?.addEventListener("click", refreshPayload);
        window.setInterval(refreshPayload, 15000);
    }

    function bindSidebarSections() {
        const sections = Array.from(document.querySelectorAll(".hc-sidebar-section"));
        if (!sections.length) {
            return;
        }

        sections.forEach((section) => {
            const collapseNode = section.querySelector(".collapse");
            if (!collapseNode) {
                return;
            }

            if (collapseNode.classList.contains("show")) {
                section.classList.add("is-expanded");
            }

            collapseNode.addEventListener("show.bs.collapse", () => {
                sections.forEach((otherSection) => {
                    otherSection.classList.remove("is-expanded");
                });
                section.classList.add("is-expanded");
            });

            collapseNode.addEventListener("hide.bs.collapse", () => {
                section.classList.remove("is-expanded");
            });
        });
    }

    function bindEmiCalculator() {
        const form = document.getElementById("emiCalculatorForm");
        if (!form) {
            return;
        }

        const principalInput = document.getElementById("emiPrincipal");
        const interestInput = document.getElementById("emiInterestRate");
        const tenureValueInput = document.getElementById("emiTenureValue");
        const tenureUnitInput = document.getElementById("emiTenureUnit");
        const monthlyValueNode = document.getElementById("emiMonthlyValue");
        const interestValueNode = document.getElementById("emiInterestValue");
        const totalValueNode = document.getElementById("emiTotalValue");
        const feedbackNode = document.getElementById("emiCalculatorFeedback");
        const resetButton = document.getElementById("emiResetButton");
        const calculateButton = document.getElementById("emiCalculateButton");

        function formatCurrency(value) {
            return new Intl.NumberFormat("en-IN", {
                style: "currency",
                currency: "INR",
                maximumFractionDigits: 2,
            }).format(value || 0);
        }

        function showFeedback(message, isError) {
            if (!feedbackNode) {
                return;
            }
            feedbackNode.textContent = message;
            feedbackNode.classList.remove("d-none", "is-success", "is-error");
            feedbackNode.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            if (!feedbackNode) {
                return;
            }
            feedbackNode.textContent = "";
            feedbackNode.classList.add("d-none");
            feedbackNode.classList.remove("is-success", "is-error");
        }

        function setResults(monthlyEmi, totalInterest, totalPayable) {
            if (monthlyValueNode) {
                monthlyValueNode.textContent = formatCurrency(monthlyEmi);
            }
            if (interestValueNode) {
                interestValueNode.textContent = formatCurrency(totalInterest);
            }
            if (totalValueNode) {
                totalValueNode.textContent = formatCurrency(totalPayable);
            }
        }

        function calculateEmi() {
            const principal = Number(principalInput?.value || 0);
            const annualRate = Number(interestInput?.value || 0);
            const tenureValue = Number(tenureValueInput?.value || 0);
            const tenureUnit = tenureUnitInput?.value || "months";
            const months = tenureUnit === "years" ? tenureValue * 12 : tenureValue;

            if (!Number.isFinite(principal) || principal <= 0) {
                setResults(0, 0, 0);
                showFeedback("Enter a valid loan amount.", true);
                return;
            }
            if (!Number.isFinite(months) || months <= 0) {
                setResults(0, 0, 0);
                showFeedback("Enter a valid tenure.", true);
                return;
            }
            if (!Number.isFinite(annualRate) || annualRate < 0) {
                setResults(0, 0, 0);
                showFeedback("Interest rate cannot be negative.", true);
                return;
            }

            const monthlyRate = annualRate / 12 / 100;
            let monthlyEmi = 0;
            if (monthlyRate === 0) {
                monthlyEmi = principal / months;
            } else {
                const factor = Math.pow(1 + monthlyRate, months);
                monthlyEmi = principal * monthlyRate * factor / (factor - 1);
            }

            const totalPayable = monthlyEmi * months;
            const totalInterest = totalPayable - principal;
            setResults(monthlyEmi, totalInterest, totalPayable);
            clearFeedback();
        }

        form.addEventListener("submit", (event) => {
            event.preventDefault();
            calculateEmi();
        });

        calculateButton?.addEventListener("click", (event) => {
            event.preventDefault();
            calculateEmi();
        });

        [principalInput, interestInput, tenureValueInput, tenureUnitInput].forEach((input) => {
            input?.addEventListener("input", calculateEmi);
            input?.addEventListener("change", calculateEmi);
        });

        resetButton?.addEventListener("click", () => {
            if (principalInput) {
                principalInput.value = "100000";
            }
            if (interestInput) {
                interestInput.value = "12";
            }
            if (tenureValueInput) {
                tenureValueInput.value = "12";
            }
            if (tenureUnitInput) {
                tenureUnitInput.value = "months";
            }
            clearFeedback();
            calculateEmi();
        });

        calculateEmi();
    }

    if (typeof initMateriallyLayout === "function") {
        initMateriallyLayout();
    }
    if (typeof initDashboardUX === "function") {
        initDashboardUX();
    }

    updateClock();
    window.setInterval(updateClock, 1000);
    animateCounters();
    renderStoredFlashMessage();
    bindSearchAndFilters();
    renderCharts();
    bindStaffCrud();
    bindLeadCrud();
    bindHandoverUpdates();
    bindFollowupConversion();
    bindInterestedLeadDecisions();
    bindLeadImport();
    bindTrainingCrud();
    bindSalaryControlCrud();
    bindLiveMonitoringPage();
    bindSidebarSections();
    bindEmiCalculator();
})();
