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
                bonusRateInput.value = button.dataset.bonus || "500";
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
    bindLeadImport();
    bindTrainingCrud();
    bindSalaryControlCrud();
    bindSidebarSections();
    bindEmiCalculator();
})();
