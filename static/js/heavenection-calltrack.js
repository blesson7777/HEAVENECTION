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

    function wait(ms) {
        return new Promise((resolve) => window.setTimeout(resolve, ms));
    }

    async function playStaffActionAnimation(button, actionType) {
        const row = button?.closest(".hc-staff-roster-row");
        if (!row) {
            return;
        }

        const actionClass = `is-animating-${actionType}`;
        row.classList.remove(
            "is-animating-delete",
            "is-animating-activate",
            "is-animating-deactivate",
            "is-animating-edit",
            "is-animating-profile"
        );
        row.classList.add(actionClass);

        const flare = document.createElement("div");
        flare.className = `hc-staff-action-flare is-${actionType}`;

        const icon = document.createElement("span");
        icon.className = "hc-staff-action-flare-icon";
        icon.innerHTML = {
            delete: '<i class="bi bi-trash3-fill"></i>',
            activate: '<i class="bi bi-play-circle-fill"></i>',
            deactivate: '<i class="bi bi-pause-circle-fill"></i>',
            edit: '<i class="bi bi-pencil-square"></i>',
            profile: '<i class="bi bi-person-vcard-fill"></i>',
        }[actionType] || '<i class="bi bi-stars"></i>';

        const label = document.createElement("strong");
        label.textContent = {
            delete: "Sending to bin",
            activate: "Waking account",
            deactivate: "Cooling account",
            edit: "Opening editor",
            profile: "Opening profile",
        }[actionType] || "Working";

        flare.append(icon, label);
        row.appendChild(flare);

        await wait(actionType === "delete" ? 720 : 560);

        flare.remove();
        row.classList.remove(actionClass);
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

            const rows = Array.from(
                tableBody.querySelectorAll("[data-filter-item], tr")
            );
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
                playStaffActionAnimation(button, "edit");
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
                    await playStaffActionAnimation(button, "delete");
                    await requestJson(`${config.teamMembersUrl}${staffId}/`, { method: "DELETE" });
                    window.location.reload();
                } catch (error) {
                    window.alert(error.message);
                }
            });
        });

        document.querySelectorAll(".js-toggle-staff-active").forEach((button) => {
            button.addEventListener("click", async () => {
                const staffId = button.dataset.staffId;
                const staffName = button.dataset.name || "this staff member";
                const isActive = button.dataset.isActive === "true";
                const confirmed = await confirmAction(
                    `${isActive ? "Deactivate" : "Activate"} ${staffName}?`,
                    {
                        title: `${isActive ? "Deactivate" : "Activate"} staff`,
                        confirmText: isActive ? "Deactivate" : "Activate",
                    }
                );
                if (!staffId || !confirmed) {
                    return;
                }
                try {
                    await playStaffActionAnimation(button, isActive ? "deactivate" : "activate");
                    await requestJson(`${config.teamMembersUrl}${staffId}/`, {
                        method: "PATCH",
                        body: JSON.stringify({ is_active: !isActive }),
                    });
                    window.location.reload();
                } catch (error) {
                    window.alert(error.message);
                }
            });
        });

        document.querySelectorAll(".js-open-staff-profile").forEach((button) => {
            button.addEventListener("click", async (event) => {
                event.preventDefault();
                const profileUrl = button.getAttribute("href");
                if (!profileUrl) {
                    return;
                }
                await playStaffActionAnimation(button, "profile");
                window.location.href = profileUrl;
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
        const openUnassignButtons = Array.from(document.querySelectorAll(".js-open-lead-unassign-mode"));
        const deleteSelectedButtons = Array.from(document.querySelectorAll(".js-delete-selected-leads-button"));
        const allocateSelectedButtons = Array.from(document.querySelectorAll(".js-allocate-selected-leads-button"));
        const unassignSelectedButtons = Array.from(document.querySelectorAll(".js-unassign-selected-leads-button"));
        const bulkDeleteForm = document.getElementById("bulkLeadDeleteForm");
        const bulkDeleteInputs = document.getElementById("bulkLeadDeleteInputs");
        const bulkUnassignForm = document.getElementById("bulkLeadUnassignForm");
        const bulkUnassignInputs = document.getElementById("bulkLeadUnassignInputs");
        const bulkAllocateModalNode = document.getElementById("bulkLeadAllocateModal");
        const bulkAllocateModal = bulkAllocateModalNode
            ? bootstrap.Modal.getOrCreateInstance(bulkAllocateModalNode)
            : null;
        const bulkAllocateForm = document.getElementById("bulkLeadAllocateForm");
        const bulkAllocateInputs = document.getElementById("bulkLeadAllocateInputs");
        const bulkAllocateStaffInput = document.getElementById("bulkLeadAllocateStaff");
        const cleanupNowForm = document.getElementById("leadCleanupNowForm");
        const cleanupDeleteMode = document.getElementById("leadCleanupDeleteMode");
        const cleanupDaysField = document.querySelector(".js-lead-cleanup-days-field");
        const cleanupCountField = document.querySelector(".js-lead-cleanup-count-field");
        const cleanupAutoMode = document.getElementById("leadAutoDeleteMode");
        const cleanupAutoDaysField = document.querySelector(".js-lead-auto-days-field");
        const cleanupAutoCountField = document.querySelector(".js-lead-auto-count-field");
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

        function visibleSelectionCheckboxes() {
            return selectionCheckboxes.filter((checkbox) => {
                const row = checkbox.closest("tr");
                return row && !row.hidden;
            });
        }

        function refreshSelectionActionState() {
            const selectedCount = selectionCheckboxes.filter((checkbox) => checkbox.checked).length;
            const visibleCheckboxes = visibleSelectionCheckboxes();
            const visibleSelectedCount = visibleCheckboxes.filter((checkbox) => checkbox.checked).length;
            deleteSelectedButtons.forEach((button) => {
                button.disabled = selectedCount === 0;
                button.textContent = selectedCount > 0 ? `Delete Marked (${selectedCount})` : "Delete Marked";
            });
            allocateSelectedButtons.forEach((button) => {
                button.disabled = selectedCount === 0;
                button.textContent = selectedCount > 0 ? `Allocate Marked (${selectedCount})` : "Allocate Marked";
            });
            unassignSelectedButtons.forEach((button) => {
                button.disabled = selectedCount === 0;
                button.textContent = selectedCount > 0 ? `Unassign Marked (${selectedCount})` : "Unassign Marked";
            });
            if (selectAllCheckbox) {
                selectAllCheckbox.checked = visibleSelectedCount > 0 && visibleSelectedCount === visibleCheckboxes.length && visibleCheckboxes.length > 0;
                selectAllCheckbox.indeterminate = visibleSelectedCount > 0 && visibleSelectedCount < visibleCheckboxes.length;
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

        function toggleCleanupFields() {
            const deleteMode = cleanupDeleteMode?.value || "age_days";
            cleanupDaysField?.classList.toggle("d-none", deleteMode !== "age_days");
            cleanupCountField?.classList.toggle("d-none", deleteMode !== "oldest_count");

            const autoMode = cleanupAutoMode?.value || "age_days";
            cleanupAutoDaysField?.classList.toggle("d-none", autoMode !== "age_days");
            cleanupAutoCountField?.classList.toggle("d-none", autoMode !== "oldest_count");
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
            unassignSelectedButtons.forEach((button) => {
                button.classList.toggle("d-none", mode !== "unassign");
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
            openUnassignButtons.forEach((button) => {
                const isUnassignMode = mode === "unassign";
                button.textContent = isUnassignMode ? "Cancel Unassign" : "Unassign Leads";
                button.classList.toggle("btn-outline-warning", !isUnassignMode);
                button.classList.toggle("btn-outline-secondary", isUnassignMode);
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

        openUnassignButtons.forEach((button) => {
            button.addEventListener("click", () => {
                toggleSelectionMode(selectionMode === "unassign" ? "" : "unassign");
            });
        });

        selectAllCheckbox?.addEventListener("change", () => {
            visibleSelectionCheckboxes().forEach((checkbox) => {
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

        unassignSelectedButtons.forEach((button) => {
            button.addEventListener("click", async () => {
                const selectedIds = selectionCheckboxes
                    .filter((checkbox) => checkbox.checked)
                    .map((checkbox) => checkbox.value);
                if (!selectedIds.length) {
                    window.alert("Select at least one lead to unassign.");
                    return;
                }
                if (!bulkUnassignForm || !bulkUnassignInputs) {
                    return;
                }
                const confirmed = await confirmAction(`Move ${selectedIds.length} selected lead(s) back to the waiting queue?`, {
                    title: "Unassign leads",
                    confirmText: "Unassign",
                });
                if (!confirmed) {
                    return;
                }
                bulkUnassignInputs.innerHTML = "";
                selectedIds.forEach((leadId) => {
                    const input = document.createElement("input");
                    input.type = "hidden";
                    input.name = "selected_lead_ids";
                    input.value = leadId;
                    bulkUnassignInputs.appendChild(input);
                });
                bulkUnassignForm.submit();
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

        cleanupDeleteMode?.addEventListener("change", toggleCleanupFields);
        cleanupAutoMode?.addEventListener("change", toggleCleanupFields);
        toggleCleanupFields();

        cleanupNowForm?.addEventListener("submit", async (event) => {
            event.preventDefault();
            const confirmed = await confirmAction(
                cleanupDeleteMode?.value === "oldest_count"
                    ? "Delete the oldest selected number of leads now? This cannot be undone."
                    : "Delete all lead-management leads older than the selected number of days? This cannot be undone.",
                {
                    title: "Delete old leads",
                    confirmText: "Delete Now",
                }
            );
            if (!confirmed) {
                return;
            }
            cleanupNowForm.submit();
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

        document.getElementById("leadSearchInput")?.addEventListener("input", refreshSelectionActionState);
        document.querySelectorAll(".hc-filter-chip[data-filter-status]").forEach((chip) => {
            chip.addEventListener("click", () => {
                window.setTimeout(refreshSelectionActionState, 0);
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
        const smartAlertGrid = document.getElementById("liveMonitoringSmartAlerts");
        const heatmapGrid = document.getElementById("liveMonitoringQueueHeatmap");
        const supervisorRoster = document.getElementById("liveMonitoringSupervisorRoster");
        const supervisorDetail = document.getElementById("liveMonitoringSupervisorDetail");
        const supervisorFeedback = document.getElementById("liveMonitoringSupervisorFeedback");
        const activeGrid = document.getElementById("liveMonitoringActiveGrid");
        const alertGrid = document.getElementById("liveMonitoringAlertGrid");
        const liveBoardSection = document.getElementById("ccLiveBoard");
        const liveBoardStats = document.getElementById("liveMonitoringBoardStats");
        const liveBoardPulse = document.getElementById("liveMonitoringBoardPulse");
        const liveBoardPerformanceGraph = document.getElementById("liveMonitoringPerformanceGraph");
        const liveBoardFullscreenButton = document.getElementById("liveBoardFullscreenButton");
        const liveBoardFullscreenLabel = document.getElementById("liveBoardFullscreenLabel");
        const liveBoardFullscreenIcon = document.getElementById("liveBoardFullscreenIcon");
        const spotlightGrid = document.getElementById("liveMonitoringSpotlightGrid");
        const staffGrid = document.getElementById("liveMonitoringStaffGrid");
        const teamMemberUrlTemplate = root.dataset.teamMemberUrlTemplate || "";
        const profileUrlTemplate = root.dataset.profileUrlTemplate || "";
        const workReviewUrl = root.dataset.workReviewUrl || "/work-review/";
        const callsUrl = root.dataset.callsUrl || "/calls/";
        const generatedAtNode = document.getElementById("liveMonitoringGeneratedAt");
        const syncBadge = document.getElementById("liveMonitoringSyncBadge");
        const syncStateNode = document.getElementById("liveMonitoringSyncState");
        const syncDetailNode = document.getElementById("liveMonitoringSyncDetail");
        const nextRefreshNode = document.getElementById("liveMonitoringNextRefresh");
        const refreshButton = document.getElementById("liveMonitoringRefreshButton");
        const fullscreenButton = document.getElementById("liveMonitoringFullscreenButton");
        const fullscreenLabel = document.getElementById("liveMonitoringFullscreenLabel");
        const fullscreenIcon = document.getElementById("liveMonitoringFullscreenIcon");
        const supervisorSearchInput = document.getElementById("liveMonitoringStaffSearch");
        const supervisorStatusSelect = document.getElementById("liveMonitoringStaffStatus");
        const supervisorSortSelect = document.getElementById("liveMonitoringStaffSort");
        const selectAllVisibleButton = document.getElementById("liveMonitoringSelectAllButton");
        const clearSelectionButton = document.getElementById("liveMonitoringClearSelectionButton");
        const selectionSummaryNode = document.getElementById("liveMonitoringSelectionSummary");
        const liveRefreshMs = 5000;
        let refreshInFlight = false;
        let refreshTimer = null;
        let countdownTimer = null;
        let nextRefreshAt = null;
        let latestStaffRows = [];
        let selectedStaffId = "";
        const selectedStaffIds = new Set();
        let supervisorSearchTerm = "";
        let supervisorStatusFilter = "all";
        let supervisorSortMode = "priority";

        function asNumber(value) {
            const number = Number(value || 0);
            return Number.isFinite(number) ? number : 0;
        }

        const focusModeClass = "hc-live-monitoring-focus";
        const liveBoardFocusClass = "hc-liveboard-focus";
        let fallbackFocusMode = false;
        let fallbackBoardFocusMode = false;

        function isFullscreenSupported() {
            return Boolean(root?.requestFullscreen && document?.exitFullscreen);
        }

        function isRootFullscreen() {
            return document.fullscreenElement === root;
        }

        function isLiveBoardFullscreen() {
            return document.fullscreenElement === liveBoardSection;
        }

        function applyFocusMode(active) {
            root.classList.toggle("is-fullscreen", active);
            document.body.classList.toggle(focusModeClass, active);
            document.documentElement.classList.toggle(focusModeClass, active);
        }

        function applyLiveBoardFocusMode(active) {
            if (!liveBoardSection) {
                return;
            }
            liveBoardSection.classList.toggle("is-board-fullscreen", active);
            document.body.classList.toggle(liveBoardFocusClass, active);
            document.documentElement.classList.toggle(liveBoardFocusClass, active);
        }

        function isFocusModeActive() {
            return isRootFullscreen() || fallbackFocusMode;
        }

        function isLiveBoardFocusModeActive() {
            return isLiveBoardFullscreen() || fallbackBoardFocusMode;
        }

        function syncFullscreenUi() {
            if (!fullscreenButton) {
                return;
            }
            const active = isFocusModeActive();
            applyFocusMode(active);
            if (fullscreenLabel) {
                if (isFullscreenSupported()) {
                    fullscreenLabel.textContent = active ? "Exit Full Screen" : "Enter Full Screen";
                } else {
                    fullscreenLabel.textContent = active ? "Exit Focus Mode" : "Focus Mode";
                }
            }
            if (fullscreenIcon) {
                fullscreenIcon.className = active ? "bi bi-fullscreen-exit" : "bi bi-arrows-fullscreen";
            }
            fullscreenButton.setAttribute("aria-pressed", active ? "true" : "false");
        }

        function syncLiveBoardFullscreenUi() {
            if (!liveBoardFullscreenButton) {
                return;
            }
            const active = isLiveBoardFocusModeActive();
            applyLiveBoardFocusMode(active);
            if (liveBoardFullscreenLabel) {
                liveBoardFullscreenLabel.textContent = active ? "Exit Live Board Full Screen" : "Open Live Board Full Screen";
            }
            if (liveBoardFullscreenIcon) {
                liveBoardFullscreenIcon.className = active ? "bi bi-fullscreen-exit" : "bi bi-bounding-box-circles";
            }
            liveBoardFullscreenButton.setAttribute("aria-pressed", active ? "true" : "false");
        }

        async function toggleFullscreenMode() {
            const targetState = !isFocusModeActive();

            if (!isFullscreenSupported()) {
                fallbackFocusMode = targetState;
                syncFullscreenUi();
                return;
            }

            try {
                if (!targetState) {
                    fallbackFocusMode = false;
                    if (isRootFullscreen()) {
                        await document.exitFullscreen();
                    }
                } else {
                    fallbackFocusMode = false;
                    await root.requestFullscreen();
                }
            } catch (error) {
                // If browser fullscreen is blocked, keep focus mode available as a fallback.
                fallbackFocusMode = targetState;
            } finally {
                syncFullscreenUi();
            }
        }

        async function toggleLiveBoardFullscreenMode() {
            if (!liveBoardSection) {
                return;
            }
            const targetState = !isLiveBoardFocusModeActive();

            if (!isFullscreenSupported()) {
                fallbackBoardFocusMode = targetState;
                syncLiveBoardFullscreenUi();
                return;
            }

            try {
                if (!targetState) {
                    fallbackBoardFocusMode = false;
                    if (isLiveBoardFullscreen()) {
                        await document.exitFullscreen();
                    }
                } else {
                    fallbackBoardFocusMode = false;
                    await liveBoardSection.requestFullscreen();
                }
            } catch (error) {
                fallbackBoardFocusMode = targetState;
            } finally {
                syncLiveBoardFullscreenUi();
            }
        }

        function withTemplateId(urlTemplate, staffId) {
            if (!urlTemplate || !staffId) {
                return "";
            }
            return urlTemplate.replace("00000000-0000-0000-0000-000000000000", staffId);
        }

        function resolveTeamMemberUrl(staffId) {
            if (!staffId) {
                return "";
            }
            const fromTemplate = withTemplateId(teamMemberUrlTemplate, staffId);
            if (fromTemplate) {
                return fromTemplate;
            }
            const base = window.heavenectionAdmin?.teamMembersUrl || "";
            if (!base) {
                return "";
            }
            return base.endsWith("/") ? `${base}${staffId}/` : `${base}/${staffId}/`;
        }

        function resolveProfileUrl(staffId) {
            if (!staffId) {
                return "#";
            }
            const fromTemplate = withTemplateId(profileUrlTemplate, staffId);
            if (fromTemplate) {
                return fromTemplate;
            }
            return `/staff/${staffId}/`;
        }

        function resolveStaffId(row) {
            const directId = String(row?.id || "").trim();
            if (directId) {
                return directId;
            }
            const rowPhone = String(row?.phone || "").trim();
            if (!rowPhone) {
                return "";
            }
            const match = latestStaffRows.find((staffRow) => String(staffRow?.phone || "").trim() === rowPhone);
            return String(match?.id || "").trim();
        }

        function resolveProfileUrlForRow(row) {
            return resolveProfileUrl(resolveStaffId(row));
        }

        function normalizeStaffText(value) {
            return String(value || "").trim().toLowerCase();
        }

        function matchesSupervisorStatus(row, filterValue) {
            switch (filterValue) {
            case "on_call":
                return Boolean(row?.is_on_call);
            case "online":
                return row?.online_label === "Online";
            case "away":
                return row?.online_label === "Away" || row?.online_label === "Warning";
            case "review":
                return row?.quality_label === "Review Needed" || row?.quality_label === "Needs Attention";
            case "offline":
                return row?.online_label === "Offline";
            default:
                return true;
            }
        }

        function getSupervisorRosterRows(rows) {
            const query = normalizeStaffText(supervisorSearchTerm);
            const filtered = (Array.isArray(rows) ? rows : []).filter((row) => {
                if (!matchesSupervisorStatus(row, supervisorStatusFilter)) {
                    return false;
                }
                if (!query) {
                    return true;
                }
                const haystack = [
                    normalizeStaffText(row?.name),
                    normalizeStaffText(row?.phone),
                ].join(" ");
                return haystack.includes(query);
            });

            return filtered.slice().sort((left, right) => {
                if (supervisorSortMode === "name") {
                    return String(left?.name || "").localeCompare(String(right?.name || ""));
                }
                if (supervisorSortMode === "calls") {
                    return asNumber(right?.calls_today) - asNumber(left?.calls_today)
                        || String(left?.name || "").localeCompare(String(right?.name || ""));
                }
                if (supervisorSortMode === "queue") {
                    return asNumber(right?.assigned_leads) - asNumber(left?.assigned_leads)
                        || String(left?.name || "").localeCompare(String(right?.name || ""));
                }
                if (supervisorSortMode === "quality") {
                    return asNumber(left?.quality_score) - asNumber(right?.quality_score)
                        || String(left?.name || "").localeCompare(String(right?.name || ""));
                }

                const leftReview = left?.quality_label === "Review Needed" || left?.quality_label === "Needs Attention" ? 1 : 0;
                const rightReview = right?.quality_label === "Review Needed" || right?.quality_label === "Needs Attention" ? 1 : 0;
                return (right?.is_on_call ? 1 : 0) - (left?.is_on_call ? 1 : 0)
                    || rightReview - leftReview
                    || riskScore(right) - riskScore(left)
                    || asNumber(right?.assigned_leads) - asNumber(left?.assigned_leads)
                    || String(left?.name || "").localeCompare(String(right?.name || ""));
            });
        }

        function renderSelectionSummary(filteredRows) {
            if (!selectionSummaryNode) {
                return;
            }

            const selectedRows = filteredRows.filter((row) => selectedStaffIds.has(resolveStaffId(row)));
            const scopeRows = selectedRows.length ? selectedRows : filteredRows;
            if (!scopeRows.length) {
                selectionSummaryNode.innerHTML = "<div class=\"hc-work-review-empty-note\">No staff match this filter.</div>";
                return;
            }

            const totalCalls = scopeRows.reduce((sum, row) => sum + asNumber(row.calls_today), 0);
            const totalQueue = scopeRows.reduce((sum, row) => sum + asNumber(row.assigned_leads), 0);
            const totalConverted = scopeRows.reduce((sum, row) => sum + asNumber(row.converted_today), 0);
            const onCallCount = scopeRows.filter((row) => row?.is_on_call).length;
            const reviewCount = scopeRows.filter((row) => (
                row?.quality_label === "Review Needed" || row?.quality_label === "Needs Attention"
            )).length;
            const averageQuality = Math.round(scopeRows.reduce((sum, row) => sum + asNumber(row.quality_score), 0) / scopeRows.length);

            selectionSummaryNode.innerHTML = `
                <div class="hc-live-selection-head">
                    <strong>${selectedRows.length ? `${selectedRows.length} selected staff` : `${filteredRows.length} visible staff`}</strong>
                    <small>${selectedRows.length ? "Performance snapshot from selected staff." : "Performance snapshot from current filtered view."}</small>
                </div>
                <div class="hc-live-selection-metrics">
                    <span><strong>${scopeRows.length}</strong> team members</span>
                    <span><strong>${onCallCount}</strong> on call now</span>
                    <span><strong>${totalCalls}</strong> calls today</span>
                    <span><strong>${totalConverted}</strong> success today</span>
                    <span><strong>${totalQueue}</strong> queued leads</span>
                    <span><strong>${averageQuality}</strong> avg quality</span>
                    <span><strong>${reviewCount}</strong> need review</span>
                </div>
                <div class="hc-live-selection-links">
                    ${scopeRows.slice(0, 12).map((row) => `
                        <a href="${escapeHtml(resolveProfileUrlForRow(row))}" class="hc-live-selection-link">
                            ${escapeHtml(row?.name || "Staff")}
                        </a>
                    `).join("")}
                    ${scopeRows.length > 12 ? `<span class="hc-live-selection-more">+${scopeRows.length - 12} more</span>` : ""}
                </div>
            `;
        }

        function bindProfileCardNavigation(container) {
            if (!container) {
                return;
            }
            container.querySelectorAll(".js-live-profile-card").forEach((card) => {
                const profileUrl = card.dataset.profileUrl || "";
                if (!profileUrl || profileUrl === "#") {
                    return;
                }
                card.addEventListener("click", (event) => {
                    const interactiveTarget = event.target.closest("a, button, input, select, textarea, label");
                    if (interactiveTarget) {
                        return;
                    }
                    window.location.href = profileUrl;
                });
                card.addEventListener("keydown", (event) => {
                    if (event.key === "Enter" || event.key === " ") {
                        event.preventDefault();
                        window.location.href = profileUrl;
                    }
                });
            });
        }

        function clearSupervisorFeedback() {
            if (!supervisorFeedback) {
                return;
            }
            supervisorFeedback.textContent = "";
            supervisorFeedback.classList.add("d-none");
            supervisorFeedback.classList.remove("is-success", "is-error");
        }

        function showSupervisorFeedback(message, isError = false) {
            if (!supervisorFeedback) {
                return;
            }
            supervisorFeedback.textContent = message || "";
            supervisorFeedback.classList.remove("d-none", "is-success", "is-error");
            supervisorFeedback.classList.add(isError ? "is-error" : "is-success");
        }

        function buildAlertSignal(row) {
            const reasons = [];
            let priority = 0;
            const assignedLeads = asNumber(row.assigned_leads);
            const verifiedAttempts = asNumber(row.verified_attempt_count);
            const realCalls = asNumber(row.real_call_count);
            const zeroBlocks = asNumber(row.zero_only_block_count);
            const suspiciousBlocks = asNumber(row.suspicious_block_count);
            const gaps = asNumber(row.gap_count);
            const missedCallbacks = asNumber(row.missed_callbacks);

            if (row.quality_label === "Review Needed") {
                priority += 5;
                reasons.push("Quality score is in review-needed range.");
            } else if (row.quality_label === "Needs Attention") {
                priority += 3;
                reasons.push("Quality score needs attention.");
            }

            if (assignedLeads >= 45) {
                priority += 4;
                reasons.push("Queue load is very high.");
            } else if (assignedLeads >= 25) {
                priority += 2;
                reasons.push("Queue load is above normal.");
            }

            if (verifiedAttempts >= 10 && realCalls === 0) {
                priority += 4;
                reasons.push("No real conversations across verified attempts.");
            }

            if (zeroBlocks > 0) {
                priority += Math.min(3, zeroBlocks + 1);
                reasons.push(`${zeroBlocks} zero-talk block(s) detected.`);
            }

            if (suspiciousBlocks > 0) {
                priority += Math.min(3, suspiciousBlocks + 1);
                reasons.push(`${suspiciousBlocks} review block(s) need checking.`);
            }

            if (gaps >= 6) {
                priority += 2;
                reasons.push("Large uncounted gap pattern is visible.");
            }

            if ((row.online_label === "Away" || row.online_label === "Warning") && assignedLeads >= 12) {
                priority += 2;
                reasons.push("Staff is away while queue remains pending.");
            }

            if (missedCallbacks > 0) {
                priority += 2;
                reasons.push(`${missedCallbacks} scheduled follow-up lead(s) are pending.`);
            }

            if (!priority) {
                return null;
            }

            let tone = "low";
            if (priority >= 9) {
                tone = "critical";
            } else if (priority >= 6) {
                tone = "high";
            } else if (priority >= 3) {
                tone = "medium";
            }
            return {
                row,
                priority,
                tone,
                reasons,
            };
        }

        function buildSmartAlerts(rows) {
            return (Array.isArray(rows) ? rows : [])
                .map((row) => buildAlertSignal(row))
                .filter(Boolean)
                .sort((left, right) => (
                    right.priority - left.priority
                    || asNumber(right.row.assigned_leads) - asNumber(left.row.assigned_leads)
                    || left.row.name.localeCompare(right.row.name)
                ))
                .slice(0, 10);
        }

        function renderSmartAlerts(rows) {
            if (!smartAlertGrid) {
                return;
            }
            const alerts = buildSmartAlerts(rows);
            if (!alerts.length) {
                smartAlertGrid.innerHTML = '<div class="hc-work-review-empty-note">No urgent smart alerts right now.</div>';
                return;
            }
            smartAlertGrid.innerHTML = alerts.map((alert) => `
                <article class="hc-live-smart-alert-card is-${escapeHtml(alert.tone)}">
                    <div class="d-flex align-items-start justify-content-between gap-2">
                        <div class="hc-staff-persona">
                            <span class="hc-staff-avatar">${escapeHtml((alert.row.name || "S").slice(0, 1).toUpperCase())}</span>
                            <div class="hc-staff-persona-copy">
                                <strong>${escapeHtml(alert.row.name || "Staff")}</strong>
                                <span>${escapeHtml(alert.row.phone || "--")}</span>
                                <small>${escapeHtml(alert.row.session_state_label || "--")}</small>
                            </div>
                        </div>
                        <span class="hc-live-alert-severity is-${escapeHtml(alert.tone)}">${escapeHtml(alert.tone.toUpperCase())}</span>
                    </div>
                    <div class="hc-live-caption mt-3">
                        ${escapeHtml(alert.reasons[0] || "Action needed.")}
                    </div>
                    <div class="hc-live-monitor-metrics mt-3">
                        <span>${asNumber(alert.row.assigned_leads)} queue</span>
                        <span>${asNumber(alert.row.real_call_count)} real calls</span>
                        <span>${asNumber(alert.row.zero_only_block_count)} zero blocks</span>
                        <span>${asNumber(alert.row.gap_count)} gaps</span>
                    </div>
                    <button type="button" class="btn btn-outline-light btn-sm mt-3 js-live-open-supervisor" data-staff-id="${escapeHtml(resolveStaffId(alert.row))}">
                        Open In Action Center
                    </button>
                </article>
            `).join("");
            smartAlertGrid.querySelectorAll(".js-live-open-supervisor").forEach((button) => {
                button.addEventListener("click", () => {
                    const staffId = button.dataset.staffId || "";
                    if (!staffId) {
                        return;
                    }
                    selectedStaffId = staffId;
                    renderSupervisorCenterEnhanced(latestStaffRows);
                    supervisorDetail?.scrollIntoView({ behavior: "smooth", block: "start" });
                });
            });
        }

        function queueTone(assignedLeads) {
            if (assignedLeads >= 60) {
                return { level: "critical", label: "Critical" };
            }
            if (assignedLeads >= 35) {
                return { level: "high", label: "High" };
            }
            if (assignedLeads >= 15) {
                return { level: "medium", label: "Medium" };
            }
            if (assignedLeads > 0) {
                return { level: "light", label: "Light" };
            }
            return { level: "idle", label: "Idle" };
        }

        function riskScore(row) {
            const qualityPenalty = Math.max(0, 100 - asNumber(row.quality_score));
            const blockPenalty = (asNumber(row.zero_only_block_count) * 10) + (asNumber(row.suspicious_block_count) * 7);
            const gapPenalty = Math.min(20, asNumber(row.gap_count) * 2);
            return Math.max(0, Math.min(100, Math.round((qualityPenalty * 0.55) + blockPenalty + gapPenalty)));
        }

        function renderQueueHeatmap(rows) {
            if (!heatmapGrid) {
                return;
            }
            const sortedRows = (Array.isArray(rows) ? rows : []).slice().sort((left, right) => (
                asNumber(right.assigned_leads) - asNumber(left.assigned_leads)
                || asNumber(right.calls_today) - asNumber(left.calls_today)
                || left.name.localeCompare(right.name)
            ));
            if (!sortedRows.length) {
                heatmapGrid.innerHTML = '<div class="hc-work-review-empty-note">No queue health data is available.</div>';
                return;
            }
            heatmapGrid.innerHTML = sortedRows.map((row) => {
                const assignedLeads = asNumber(row.assigned_leads);
                const queue = queueTone(assignedLeads);
                const queuePercent = Math.min(100, Math.round((assignedLeads / 60) * 100));
                const risk = riskScore(row);
                return `
                    <article class="hc-live-heatmap-cell is-${escapeHtml(queue.level)}">
                        <div class="d-flex align-items-start justify-content-between gap-2">
                            <div>
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <div class="hc-live-caption">${escapeHtml(row.phone || "--")}</div>
                            </div>
                            <span class="hc-live-heatmap-tag is-${escapeHtml(queue.level)}">${escapeHtml(queue.label)}</span>
                        </div>
                        <div class="hc-live-heatmap-meter">
                            <span>Queue ${assignedLeads}</span>
                            <div class="hc-live-heatmap-bar">
                                <span style="width: ${queuePercent}%;"></span>
                            </div>
                        </div>
                        <div class="hc-live-heatmap-meter">
                            <span>Risk ${risk}%</span>
                            <div class="hc-live-heatmap-bar is-risk">
                                <span style="width: ${risk}%;"></span>
                            </div>
                        </div>
                        <div class="hc-live-monitor-metrics">
                            <span>${asNumber(row.calls_today)} calls</span>
                            <span>${asNumber(row.converted_today)} success</span>
                            <span>${asNumber(row.real_call_count)} real</span>
                            <span>${asNumber(row.zero_second_attempt_count)} zero-sec</span>
                        </div>
                    </article>
                `;
            }).join("");
        }

        function renderSupervisorCenter(rows) {
            return renderSupervisorCenterEnhanced(rows);
            if (!supervisorRoster || !supervisorDetail) {
                return;
            }
            const rosterRows = Array.isArray(rows) ? rows : [];
            const knownStaffIds = new Set(rosterRows.map((row) => resolveStaffId(row)).filter(Boolean));
            selectedStaffIds.forEach((staffId) => {
                if (!knownStaffIds.has(staffId)) {
                    selectedStaffIds.delete(staffId);
                }
            });

            const orderedRows = getSupervisorRosterRows(rosterRows);
            renderSelectionSummary(orderedRows);
            if (!orderedRows.length) {
                supervisorRoster.innerHTML = '<div class="hc-work-review-empty-note">No staff records match this filter.</div>';
                supervisorDetail.innerHTML = '<div class="hc-work-review-empty-note">No staff member selected.</div>';
                return;
            }

            if (!selectedStaffId || !orderedRows.some((row) => resolveStaffId(row) === selectedStaffId)) {
                selectedStaffId = resolveStaffId(orderedRows[0]);
            }

            supervisorRoster.innerHTML = orderedRows.map((row) => `
                <button type="button" class="hc-live-supervisor-item ${row.id === selectedStaffId ? "is-selected" : ""}" data-staff-id="${escapeHtml(row.id || "")}">
                    <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                    <span class="hc-live-supervisor-copy">
                        <strong>${escapeHtml(row.name || "Staff")}</strong>
                        <small>${escapeHtml(row.online_label || "Offline")} · ${asNumber(row.assigned_leads)} queue</small>
                    </span>
                    <span class="hc-status hc-status-${escapeHtml(row.quality_tone || "muted")}">${escapeHtml(row.quality_label || "No Recent Activity")}</span>
                </button>
            `).join("");
            supervisorRoster.querySelectorAll(".hc-live-supervisor-item").forEach((button) => {
                button.addEventListener("click", () => {
                    selectedStaffId = button.dataset.staffId || "";
                    clearSupervisorFeedback();
                    renderSupervisorCenter(latestStaffRows);
                });
            });

            const selectedRow = orderedRows.find((row) => row.id === selectedStaffId);
            if (!selectedRow) {
                supervisorDetail.innerHTML = '<div class="hc-work-review-empty-note">No staff member selected.</div>';
                return;
            }

            const profileUrl = resolveProfileUrl(selectedRow.id);
            const openCallsUrl = `${callsUrl}${callsUrl.includes("?") ? "&" : "?"}staff=${encodeURIComponent(selectedRow.id)}`;
            const reviewUrl = `${workReviewUrl}${workReviewUrl.includes("?") ? "&" : "?"}staff=${encodeURIComponent(selectedRow.id)}`;
            const isActive = selectedRow.is_active !== false;
            supervisorDetail.innerHTML = `
                <div class="hc-live-supervisor-head">
                    <div class="hc-staff-persona">
                        <span class="hc-staff-avatar">${escapeHtml((selectedRow.name || "S").slice(0, 1).toUpperCase())}</span>
                        <div class="hc-staff-persona-copy">
                            <strong>${escapeHtml(selectedRow.name || "Staff")}</strong>
                            <span>${escapeHtml(selectedRow.phone || "--")}</span>
                            <small>${escapeHtml(selectedRow.session_state_label || "--")}</small>
                        </div>
                    </div>
                    <span class="hc-status hc-status-${escapeHtml(selectedRow.status_tone || "muted")}">${escapeHtml(selectedRow.online_label || "Offline")}</span>
                </div>
                <div class="hc-live-supervisor-metrics">
                    <span>${escapeHtml(selectedRow.active_hours_today || "0.0h")} worked</span>
                    <span>${asNumber(selectedRow.calls_today)} calls</span>
                    <span>${asNumber(selectedRow.assigned_leads)} queue</span>
                    <span>${asNumber(selectedRow.zero_only_block_count)} zero blocks</span>
                    <span>${asNumber(selectedRow.gap_count)} gaps</span>
                    <span>${asNumber(selectedRow.quality_score)} quality score</span>
                </div>
                <p class="hc-live-caption">${escapeHtml(selectedRow.quality_note || selectedRow.status_note || "")}</p>
                <div class="hc-live-supervisor-actions">
                    <a href="${escapeHtml(profileUrl)}" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-person-vcard"></i>
                        <span>Open Profile</span>
                    </a>
                    <a href="${escapeHtml(openCallsUrl)}" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-telephone-forward-fill"></i>
                        <span>Open Calls</span>
                    </a>
                    <a href="${escapeHtml(reviewUrl)}" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-shield-exclamation"></i>
                        <span>Open Review</span>
                    </a>
                    <button type="button" class="btn btn-sm ${isActive ? "btn-outline-warning" : "btn-outline-success"} js-live-toggle-staff" data-staff-id="${escapeHtml(selectedRow.id || "")}" data-next-active="${isActive ? "false" : "true"}" data-staff-name="${escapeHtml(selectedRow.name || "Staff")}">
                        <i class="bi ${isActive ? "bi-person-dash" : "bi-person-check"}"></i>
                        <span>${isActive ? "Disable Access" : "Activate Access"}</span>
                    </button>
                </div>
            `;
            supervisorDetail.querySelectorAll(".js-live-toggle-staff").forEach((button) => {
                button.addEventListener("click", async () => {
                    const staffId = button.dataset.staffId || "";
                    const staffName = button.dataset.staffName || "Staff";
                    const nextActive = button.dataset.nextActive === "true";
                    const detailUrl = resolveTeamMemberUrl(staffId);
                    if (!detailUrl) {
                        showSupervisorFeedback("Staff control URL is not available right now.", true);
                        return;
                    }
                    button.disabled = true;
                    clearSupervisorFeedback();
                    try {
                        await requestJson(detailUrl, {
                            method: "PATCH",
                            body: JSON.stringify({ is_active: nextActive }),
                        });
                        showSupervisorFeedback(`${staffName} is now ${nextActive ? "active" : "disabled"}.`, false);
                        refreshPayload({ silent: false });
                    } catch (error) {
                        showSupervisorFeedback(error.message || "Unable to update staff access right now.", true);
                    } finally {
                        button.disabled = false;
                    }
                });
            });
        }

        function renderSupervisorCenterEnhanced(rows) {
            if (!supervisorRoster || !supervisorDetail) {
                return;
            }
            const rosterRows = Array.isArray(rows) ? rows : [];
            const knownStaffIds = new Set(rosterRows.map((row) => resolveStaffId(row)).filter(Boolean));
            selectedStaffIds.forEach((staffId) => {
                if (!knownStaffIds.has(staffId)) {
                    selectedStaffIds.delete(staffId);
                }
            });

            const orderedRows = getSupervisorRosterRows(rosterRows);
            renderSelectionSummary(orderedRows);
            if (!orderedRows.length) {
                supervisorRoster.innerHTML = '<div class="hc-work-review-empty-note">No staff records match this filter.</div>';
                supervisorDetail.innerHTML = '<div class="hc-work-review-empty-note">No staff member selected.</div>';
                return;
            }

            if (!selectedStaffId || !orderedRows.some((row) => resolveStaffId(row) === selectedStaffId)) {
                selectedStaffId = resolveStaffId(orderedRows[0]);
            }

            supervisorRoster.innerHTML = orderedRows.map((row) => {
                const rowId = resolveStaffId(row);
                const isMarked = selectedStaffIds.has(rowId);
                const profileUrl = resolveProfileUrl(rowId);
                return `
                    <div class="hc-live-supervisor-item ${rowId === selectedStaffId ? "is-selected" : ""}">
                        <button type="button" class="hc-live-supervisor-main js-live-open-staff" data-staff-id="${escapeHtml(rowId)}">
                            <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                            <span class="hc-live-supervisor-copy">
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <small>${escapeHtml(row.online_label || "Offline")} · ${asNumber(row.assigned_leads)} queue</small>
                            </span>
                            <span class="hc-status hc-status-${escapeHtml(row.quality_tone || "muted")}">${escapeHtml(row.quality_label || "No Recent Activity")}</span>
                        </button>
                        <div class="hc-live-supervisor-tools">
                            <a href="${escapeHtml(profileUrl)}" class="btn btn-outline-light btn-sm hc-live-supervisor-link" title="Open profile">
                                <i class="bi bi-box-arrow-up-right"></i>
                            </a>
                            <button type="button" class="btn btn-sm ${isMarked ? "btn-primary" : "btn-outline-light"} js-live-select-staff" data-staff-id="${escapeHtml(rowId)}">
                                ${isMarked ? "Selected" : "Select"}
                            </button>
                        </div>
                    </div>
                `;
            }).join("");
            supervisorRoster.querySelectorAll(".js-live-open-staff").forEach((button) => {
                button.addEventListener("click", () => {
                    selectedStaffId = button.dataset.staffId || "";
                    clearSupervisorFeedback();
                    renderSupervisorCenterEnhanced(latestStaffRows);
                });
            });
            supervisorRoster.querySelectorAll(".js-live-select-staff").forEach((button) => {
                button.addEventListener("click", () => {
                    const staffId = button.dataset.staffId || "";
                    if (!staffId) {
                        return;
                    }
                    if (selectedStaffIds.has(staffId)) {
                        selectedStaffIds.delete(staffId);
                    } else {
                        selectedStaffIds.add(staffId);
                    }
                    renderSupervisorCenterEnhanced(latestStaffRows);
                });
            });

            const selectedRow = orderedRows.find((row) => resolveStaffId(row) === selectedStaffId);
            if (!selectedRow) {
                supervisorDetail.innerHTML = '<div class="hc-work-review-empty-note">No staff member selected.</div>';
                return;
            }

            const selectedRowId = resolveStaffId(selectedRow);
            const profileUrl = resolveProfileUrl(selectedRowId);
            const openCallsUrl = `${callsUrl}${callsUrl.includes("?") ? "&" : "?"}staff=${encodeURIComponent(selectedRowId)}`;
            const reviewUrl = `${workReviewUrl}${workReviewUrl.includes("?") ? "&" : "?"}staff=${encodeURIComponent(selectedRowId)}`;
            const isActive = selectedRow.is_active !== false;
            const selectedInScope = selectedStaffIds.has(selectedRowId);

            supervisorDetail.innerHTML = `
                <div class="hc-live-supervisor-head">
                    <div class="hc-staff-persona">
                        <span class="hc-staff-avatar">${escapeHtml((selectedRow.name || "S").slice(0, 1).toUpperCase())}</span>
                        <div class="hc-staff-persona-copy">
                            <strong>${escapeHtml(selectedRow.name || "Staff")}</strong>
                            <span>${escapeHtml(selectedRow.phone || "--")}</span>
                            <small>${escapeHtml(selectedRow.session_state_label || "--")}</small>
                        </div>
                    </div>
                    <span class="hc-status hc-status-${escapeHtml(selectedRow.status_tone || "muted")}">${escapeHtml(selectedRow.online_label || "Offline")}</span>
                </div>
                <div class="hc-live-supervisor-metrics">
                    <span>${escapeHtml(selectedRow.active_hours_today || "0.0h")} worked</span>
                    <span>${asNumber(selectedRow.calls_today)} calls</span>
                    <span>${asNumber(selectedRow.assigned_leads)} queue</span>
                    <span>${asNumber(selectedRow.zero_only_block_count)} zero blocks</span>
                    <span>${asNumber(selectedRow.gap_count)} gaps</span>
                    <span>${asNumber(selectedRow.quality_score)} quality score</span>
                </div>
                <p class="hc-live-caption">${escapeHtml(selectedRow.quality_note || selectedRow.status_note || "")}</p>
                <div class="hc-live-supervisor-actions">
                    <a href="${escapeHtml(profileUrl)}" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-person-vcard"></i>
                        <span>Open Profile</span>
                    </a>
                    <a href="${escapeHtml(openCallsUrl)}" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-telephone-forward-fill"></i>
                        <span>Open Calls</span>
                    </a>
                    <a href="${escapeHtml(reviewUrl)}" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-shield-exclamation"></i>
                        <span>Open Review</span>
                    </a>
                    <button type="button" class="btn btn-sm ${selectedInScope ? "btn-primary" : "btn-outline-light"} js-live-toggle-selection" data-staff-id="${escapeHtml(selectedRowId)}">
                        <i class="bi ${selectedInScope ? "bi-check2-square" : "bi-square"}"></i>
                        <span>${selectedInScope ? "Selected" : "Select Staff"}</span>
                    </button>
                    <button type="button" class="btn btn-sm ${isActive ? "btn-outline-warning" : "btn-outline-success"} js-live-toggle-staff" data-staff-id="${escapeHtml(selectedRowId)}" data-next-active="${isActive ? "false" : "true"}" data-staff-name="${escapeHtml(selectedRow.name || "Staff")}">
                        <i class="bi ${isActive ? "bi-person-dash" : "bi-person-check"}"></i>
                        <span>${isActive ? "Disable Access" : "Activate Access"}</span>
                    </button>
                </div>
            `;

            supervisorDetail.querySelectorAll(".js-live-toggle-selection").forEach((button) => {
                button.addEventListener("click", () => {
                    const staffId = button.dataset.staffId || "";
                    if (!staffId) {
                        return;
                    }
                    if (selectedStaffIds.has(staffId)) {
                        selectedStaffIds.delete(staffId);
                    } else {
                        selectedStaffIds.add(staffId);
                    }
                    renderSupervisorCenterEnhanced(latestStaffRows);
                });
            });

            supervisorDetail.querySelectorAll(".js-live-toggle-staff").forEach((button) => {
                button.addEventListener("click", async () => {
                    const staffId = button.dataset.staffId || "";
                    const staffName = button.dataset.staffName || "Staff";
                    const nextActive = button.dataset.nextActive === "true";
                    const detailUrl = resolveTeamMemberUrl(staffId);
                    if (!detailUrl) {
                        showSupervisorFeedback("Staff control URL is not available right now.", true);
                        return;
                    }
                    button.disabled = true;
                    clearSupervisorFeedback();
                    try {
                        await requestJson(detailUrl, {
                            method: "PATCH",
                            body: JSON.stringify({ is_active: nextActive }),
                        });
                        showSupervisorFeedback(`${staffName} is now ${nextActive ? "active" : "disabled"}.`, false);
                        refreshPayload({ silent: false });
                    } catch (error) {
                        showSupervisorFeedback(error.message || "Unable to update staff access right now.", true);
                    } finally {
                        button.disabled = false;
                    }
                });
            });
        }

        function setSyncState(mode, detail) {
            if (!syncBadge) {
                return;
            }
            syncBadge.classList.remove("is-live", "is-syncing", "is-reconnecting", "is-paused");
            syncBadge.classList.add(`is-${mode}`);
            if (syncStateNode) {
                syncStateNode.textContent = {
                    live: "Live Sync Active",
                    syncing: "Syncing Live Data",
                    reconnecting: "Reconnecting",
                    paused: "Live Sync Paused",
                }[mode] || "Live Sync Active";
            }
            if (syncDetailNode) {
                syncDetailNode.textContent = detail || "Refreshing this dashboard automatically.";
            }
        }

        function updateCountdown() {
            if (!nextRefreshNode) {
                return;
            }
            if (document.hidden || !nextRefreshAt) {
                nextRefreshNode.textContent = "--";
                return;
            }
            const remainingMs = Math.max(0, nextRefreshAt - Date.now());
            nextRefreshNode.textContent = `${Math.ceil(remainingMs / 1000)}s`;
        }

        function ensureCountdown() {
            if (countdownTimer) {
                return;
            }
            countdownTimer = window.setInterval(updateCountdown, 1000);
        }

        function clearScheduledRefresh() {
            if (refreshTimer) {
                window.clearTimeout(refreshTimer);
                refreshTimer = null;
            }
            nextRefreshAt = null;
            updateCountdown();
        }

        function scheduleRefresh(delayMs = liveRefreshMs) {
            clearScheduledRefresh();
            if (document.hidden) {
                setSyncState("paused", "Tab is hidden. Live sync will resume when you return.");
                return;
            }
            nextRefreshAt = Date.now() + delayMs;
            updateCountdown();
            refreshTimer = window.setTimeout(() => {
                refreshPayload({ silent: true });
            }, delayMs);
        }

        function buildLiveUrl() {
            if (!apiUrl) {
                return "";
            }
            const separator = apiUrl.includes("?") ? "&" : "?";
            return `${apiUrl}${separator}_live=${Date.now()}`;
        }

        function averageValue(values) {
            if (!Array.isArray(values) || !values.length) {
                return 0;
            }
            const total = values.reduce((sum, value) => sum + asNumber(value), 0);
            return total / values.length;
        }

        function isLiveActiveRow(row) {
            return Boolean(row?.is_on_call || row?.online_label === "Online");
        }

        function boardPerformanceScore(row) {
            return (
                (asNumber(row.quality_score) * 0.55)
                + (Math.min(asNumber(row.calls_today), 60) * 0.65)
                + (Math.min(asNumber(row.real_call_count), 45) * 0.45)
                - (Math.min(asNumber(row.gap_count), 10) * 2)
                - (Math.min(asNumber(row.zero_only_block_count), 6) * 4)
            );
        }

        function renderLiveBoardStats(rows) {
            if (!liveBoardStats) {
                return;
            }
            const roster = Array.isArray(rows) ? rows : [];
            const activeRows = roster.filter((row) => isLiveActiveRow(row));
            const onCallRows = roster.filter((row) => row?.is_on_call);
            const reviewRows = roster.filter((row) => (
                row?.quality_label === "Review Needed"
                || row?.quality_label === "Needs Attention"
                || row?.online_label === "Away"
                || row?.online_label === "Warning"
            ));
            const avgQuality = Math.round(averageValue(activeRows.map((row) => row.quality_score)));
            const activeCalls = activeRows.reduce((sum, row) => sum + asNumber(row.calls_today), 0);
            const activeQueue = activeRows.reduce((sum, row) => sum + asNumber(row.assigned_leads), 0);
            liveBoardStats.innerHTML = `
                <article class="hc-liveboard-stat-card is-aqua">
                    <span>Live in the floor</span>
                    <strong>${activeRows.length}</strong>
                    <small>${onCallRows.length} staff are currently on a live customer call.</small>
                </article>
                <article class="hc-liveboard-stat-card is-violet">
                    <span>Average quality</span>
                    <strong>${avgQuality || 0}</strong>
                    <small>Current active-staff quality score average.</small>
                </article>
                <article class="hc-liveboard-stat-card is-amber">
                    <span>Calls in motion</span>
                    <strong>${activeCalls}</strong>
                    <small>Total calls logged today by staff who are active right now.</small>
                </article>
                <article class="hc-liveboard-stat-card is-rose">
                    <span>Queue pressure</span>
                    <strong>${activeQueue}</strong>
                    <small>${reviewRows.length} staff need attention or review.</small>
                </article>
            `;
        }

        function renderLiveBoardPulse(rows) {
            if (!liveBoardPulse) {
                return;
            }
            const orderedRows = (Array.isArray(rows) ? rows : [])
                .filter((row) => isLiveActiveRow(row))
                .sort((left, right) => (
                    Number(Boolean(right.is_on_call)) - Number(Boolean(left.is_on_call))
                    || asNumber(right.calls_today) - asNumber(left.calls_today)
                    || asNumber(right.quality_score) - asNumber(left.quality_score)
                ))
                .slice(0, 6);
            if (!orderedRows.length) {
                liveBoardPulse.innerHTML = '<div class="hc-work-review-empty-note">No active staff pulse is available right now.</div>';
                return;
            }
            liveBoardPulse.innerHTML = orderedRows.map((row) => {
                const statusLabel = row.is_on_call ? "Speaking with customer" : "Ready for next customer";
                const currentLead = row.current_call?.lead_name || "Next lead ready";
                const currentPhone = row.current_call?.lead_phone || row.phone || "--";
                const durationLabel = row.current_call?.duration_label || row.active_hours_today || "0.0h";
                return `
                    <article class="hc-liveboard-pulse-card ${row.is_on_call ? "is-oncall" : "is-ready"} js-live-profile-card" data-profile-url="${escapeHtml(resolveProfileUrlForRow(row))}" role="button" tabindex="0">
                        <div class="hc-liveboard-pulse-head">
                            <div class="hc-staff-persona">
                                <span class="hc-staff-avatar">${escapeHtml((row.name || "S").slice(0, 1).toUpperCase())}</span>
                                <div class="hc-staff-persona-copy">
                                    <strong>${escapeHtml(row.name || "Staff")}</strong>
                                    <span>${escapeHtml(statusLabel)}</span>
                                </div>
                            </div>
                            <span class="hc-status hc-status-${escapeHtml(row.status_tone || "muted")}">${escapeHtml(row.online_label || "Offline")}</span>
                        </div>
                        <div class="hc-liveboard-call-lane">
                            <div class="hc-liveboard-waveform" aria-hidden="true">
                                <span></span><span></span><span></span><span></span><span></span>
                            </div>
                            <div class="hc-liveboard-call-copy">
                                <strong>${escapeHtml(currentLead)}</strong>
                                <span>${escapeHtml(currentPhone)}</span>
                            </div>
                            <div class="hc-liveboard-call-time">${escapeHtml(durationLabel)}</div>
                        </div>
                    </article>
                `;
            }).join("");
            bindProfileCardNavigation(liveBoardPulse);
        }

        function renderLiveBoardPerformance(rows) {
            if (!liveBoardPerformanceGraph) {
                return;
            }
            const orderedRows = (Array.isArray(rows) ? rows : [])
                .slice()
                .sort((left, right) => (
                    boardPerformanceScore(right) - boardPerformanceScore(left)
                    || asNumber(right.calls_today) - asNumber(left.calls_today)
                ))
                .slice(0, 8);
            if (!orderedRows.length) {
                liveBoardPerformanceGraph.innerHTML = '<div class="hc-work-review-empty-note">No performance graph data is available right now.</div>';
                return;
            }
            const maxCalls = Math.max(1, ...orderedRows.map((row) => asNumber(row.calls_today)));
            const maxHours = Math.max(1, ...orderedRows.map((row) => asNumber(String(row.active_hours_today || "0").replace(/[^\d.]/g, ""))));
            const maxQueue = Math.max(1, ...orderedRows.map((row) => asNumber(row.assigned_leads)));
            liveBoardPerformanceGraph.innerHTML = orderedRows.map((row) => {
                const callsPercent = Math.min(100, Math.round((asNumber(row.calls_today) / maxCalls) * 100));
                const qualityPercent = Math.min(100, Math.round(asNumber(row.quality_score)));
                const queuePercent = Math.min(100, Math.round((asNumber(row.assigned_leads) / maxQueue) * 100));
                const hoursValue = asNumber(String(row.active_hours_today || "0").replace(/[^\d.]/g, ""));
                const hoursPercent = Math.min(100, Math.round((hoursValue / maxHours) * 100));
                return `
                    <article class="hc-liveboard-graph-row js-live-profile-card" data-profile-url="${escapeHtml(resolveProfileUrlForRow(row))}" role="button" tabindex="0">
                        <div class="hc-liveboard-graph-head">
                            <div>
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <span>${escapeHtml(row.online_label || "Offline")} · ${escapeHtml(row.session_state_label || "--")}</span>
                            </div>
                            <span class="hc-liveboard-graph-score">${Math.max(0, Math.round(boardPerformanceScore(row)))}</span>
                        </div>
                        <div class="hc-liveboard-graph-bars">
                            <div class="hc-liveboard-graph-metric">
                                <label>Calls</label>
                                <div class="hc-liveboard-graph-track"><span class="is-calls" style="width:${callsPercent}%;"></span></div>
                                <strong>${asNumber(row.calls_today)}</strong>
                            </div>
                            <div class="hc-liveboard-graph-metric">
                                <label>Work</label>
                                <div class="hc-liveboard-graph-track"><span class="is-hours" style="width:${hoursPercent}%;"></span></div>
                                <strong>${escapeHtml(row.active_hours_today || "0.0h")}</strong>
                            </div>
                            <div class="hc-liveboard-graph-metric">
                                <label>Quality</label>
                                <div class="hc-liveboard-graph-track"><span class="is-quality" style="width:${qualityPercent}%;"></span></div>
                                <strong>${asNumber(row.quality_score)}</strong>
                            </div>
                            <div class="hc-liveboard-graph-metric">
                                <label>Queue</label>
                                <div class="hc-liveboard-graph-track"><span class="is-queue" style="width:${queuePercent}%;"></span></div>
                                <strong>${asNumber(row.assigned_leads)}</strong>
                            </div>
                        </div>
                    </article>
                `;
            }).join("");
            bindProfileCardNavigation(liveBoardPerformanceGraph);
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
                <article class="hc-liveboard-staff-card ${row.is_on_call ? "is-oncall" : "is-online"} js-live-profile-card" data-profile-url="${escapeHtml(resolveProfileUrlForRow(row))}" role="button" tabindex="0">
                    <div class="hc-liveboard-card-head">
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
                    <div class="hc-liveboard-card-note">${escapeHtml(row.status_note || "")}</div>
                    <div class="hc-liveboard-call-strip">
                        <div class="hc-liveboard-waveform" aria-hidden="true">
                            <span></span><span></span><span></span><span></span><span></span>
                        </div>
                        ${row.current_call ? `
                            <div class="hc-liveboard-call-copy">
                                <strong>${escapeHtml(row.current_call.lead_name || "Lead")}</strong>
                                <span>${escapeHtml(row.current_call.lead_phone || "--")}</span>
                            </div>
                            <div class="hc-liveboard-call-time">${escapeHtml(row.current_call.duration_label || "--")}</div>
                        ` : `
                            <div class="hc-liveboard-call-copy">
                                <strong>Ready for next customer</strong>
                                <span>${escapeHtml(row.last_seen || "--")}</span>
                            </div>
                            <div class="hc-liveboard-call-time">Standby</div>
                        `}
                    </div>
                    <div class="hc-liveboard-mini-metrics">
                        <span>${escapeHtml(row.active_hours_today || "0.0h")} worked</span>
                        <span>${asNumber(row.calls_today)} calls</span>
                        <span>${asNumber(row.assigned_leads)} queue</span>
                        <span>${asNumber(row.quality_score)} quality</span>
                    </div>
                    <div class="hc-liveboard-progress-block">
                        <div class="hc-liveboard-progress-row">
                            <label>Quality</label>
                            <div class="hc-liveboard-progress-track"><span class="is-quality" style="width:${Math.min(100, Math.round(asNumber(row.quality_score)))}%;"></span></div>
                        </div>
                        <div class="hc-liveboard-progress-row">
                            <label>Queue load</label>
                            <div class="hc-liveboard-progress-track"><span class="is-queue" style="width:${Math.min(100, Math.round((asNumber(row.assigned_leads) / 60) * 100))}%;"></span></div>
                        </div>
                    </div>
                    <div class="hc-live-card-actions">
                        <a href="${escapeHtml(resolveProfileUrlForRow(row))}" class="btn btn-outline-light btn-sm">
                            <i class="bi bi-person-vcard"></i>
                            <span>Open Profile</span>
                        </a>
                    </div>
                </article>
            `).join("");
            bindProfileCardNavigation(activeGrid);
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
                <article class="hc-liveboard-alert-card js-live-profile-card" data-profile-url="${escapeHtml(resolveProfileUrlForRow(row))}" role="button" tabindex="0">
                    <div class="hc-liveboard-card-head">
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
                    <div class="hc-liveboard-alert-body">
                        <p>${escapeHtml(row.quality_note || row.status_note || "")}</p>
                        <div class="hc-liveboard-alert-pills">
                            <span>${asNumber(row.gap_count)} gaps</span>
                            <span>${escapeHtml(row.gap_uncounted_label || "0s")} uncounted</span>
                            <span>${asNumber(row.zero_only_block_count)} zero-talk</span>
                            <span>${asNumber(row.invalid_short_count)} invalid short</span>
                        </div>
                        <div class="hc-liveboard-alert-caption">
                            ${escapeHtml(row.attempt_review_label || "--")}. ${asNumber(row.real_call_count)} real calls and ${asNumber(row.zero_second_attempt_count)} zero-second attempts.
                        </div>
                    </div>
                    <div class="hc-live-card-actions">
                        <a href="${escapeHtml(resolveProfileUrlForRow(row))}" class="btn btn-outline-light btn-sm">
                            <i class="bi bi-person-vcard"></i>
                            <span>Open Profile</span>
                        </a>
                    </div>
                </article>
            `).join("");
            bindProfileCardNavigation(alertGrid);
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
                <article class="hc-live-monitor-card js-live-profile-card" data-profile-url="${escapeHtml(resolveProfileUrlForRow(row))}" role="button" tabindex="0">
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
                    <div class="hc-live-card-actions mt-3">
                        <a href="${escapeHtml(resolveProfileUrlForRow(row))}" class="btn btn-outline-light btn-sm">
                            <i class="bi bi-person-vcard"></i>
                            <span>Open Profile</span>
                        </a>
                    </div>
                </article>
            `).join("");
            bindProfileCardNavigation(spotlightGrid);
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
                <article class="hc-live-staff-card js-live-profile-card" data-profile-url="${escapeHtml(resolveProfileUrlForRow(row))}" role="button" tabindex="0">
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
                    <div class="hc-live-card-actions">
                        <a href="${escapeHtml(resolveProfileUrlForRow(row))}" class="btn btn-outline-light btn-sm">
                            <i class="bi bi-person-vcard"></i>
                            <span>Open Profile</span>
                        </a>
                    </div>
                </article>
            `).join("");
            bindProfileCardNavigation(staffGrid);
        }

        function renderPayload(payload) {
            if (!payload || typeof payload !== "object") {
                return;
            }
            latestStaffRows = Array.isArray(payload.staff_rows) ? payload.staff_rows : [];
            renderSummary(payload.summary || {});
            renderLiveBoardStats(latestStaffRows);
            renderLiveBoardPulse(latestStaffRows);
            renderLiveBoardPerformance(latestStaffRows);
            renderSmartAlerts(latestStaffRows);
            renderQueueHeatmap(latestStaffRows);
            renderSupervisorCenterEnhanced(latestStaffRows);
            renderActiveGrid(latestStaffRows);
            renderAlertGrid(latestStaffRows);
            renderSpotlight(payload.spotlight_rows || []);
            renderStaffGrid(latestStaffRows);
            if (generatedAtNode) {
                generatedAtNode.textContent = payload.generated_at_label || "--";
            }
        }

        async function refreshPayload({ silent = false } = {}) {
            if (!apiUrl || refreshInFlight) {
                return;
            }
            refreshInFlight = true;
            clearScheduledRefresh();
            if (refreshButton) {
                refreshButton.disabled = true;
            }
            setSyncState("syncing", silent ? "Updating live activity in the background." : "Refreshing the latest staff activity now.");
            try {
                const payload = await requestJson(buildLiveUrl(), { method: "GET" });
                renderPayload(payload);
                setSyncState("live", "Dashboard is receiving live updates automatically.");
                scheduleRefresh(liveRefreshMs);
            } catch (error) {
                setSyncState("reconnecting", "Connection slowed down. Keeping the last live view and trying again.");
                scheduleRefresh(liveRefreshMs);
            } finally {
                refreshInFlight = false;
                if (refreshButton) {
                    refreshButton.disabled = false;
                }
            }
        }

        renderPayload(readJsonScript("heavenectionLiveMonitoringPayload"));
        setSyncState("live", "Dashboard is receiving live updates automatically.");
        ensureCountdown();
        scheduleRefresh(liveRefreshMs);
        refreshButton?.addEventListener("click", () => refreshPayload({ silent: false }));
        supervisorSearchInput?.addEventListener("input", () => {
            supervisorSearchTerm = supervisorSearchInput.value || "";
            renderSupervisorCenterEnhanced(latestStaffRows);
        });
        supervisorStatusSelect?.addEventListener("change", () => {
            supervisorStatusFilter = supervisorStatusSelect.value || "all";
            renderSupervisorCenterEnhanced(latestStaffRows);
        });
        supervisorSortSelect?.addEventListener("change", () => {
            supervisorSortMode = supervisorSortSelect.value || "priority";
            renderSupervisorCenterEnhanced(latestStaffRows);
        });
        selectAllVisibleButton?.addEventListener("click", () => {
            const visibleRows = getSupervisorRosterRows(latestStaffRows);
            visibleRows.forEach((row) => {
                const staffId = resolveStaffId(row);
                if (staffId) {
                    selectedStaffIds.add(staffId);
                }
            });
            renderSupervisorCenterEnhanced(latestStaffRows);
        });
        clearSelectionButton?.addEventListener("click", () => {
            selectedStaffIds.clear();
            renderSupervisorCenterEnhanced(latestStaffRows);
        });
        if (fullscreenButton) {
            syncFullscreenUi();
            fullscreenButton.addEventListener("click", () => {
                toggleFullscreenMode();
            });
        }
        if (liveBoardFullscreenButton) {
            syncLiveBoardFullscreenUi();
            liveBoardFullscreenButton.addEventListener("click", () => {
                toggleLiveBoardFullscreenMode();
            });
        }
        document.addEventListener("fullscreenchange", () => {
            if (!isRootFullscreen()) {
                fallbackFocusMode = false;
            }
            if (!isLiveBoardFullscreen()) {
                fallbackBoardFocusMode = false;
            }
            syncFullscreenUi();
            syncLiveBoardFullscreenUi();
        });
        document.addEventListener("keydown", (event) => {
            if (event.key !== "Escape") {
                return;
            }
            if (fallbackFocusMode && !isRootFullscreen()) {
                fallbackFocusMode = false;
                syncFullscreenUi();
            }
            if (fallbackBoardFocusMode && !isLiveBoardFullscreen()) {
                fallbackBoardFocusMode = false;
                syncLiveBoardFullscreenUi();
            }
        });
        document.addEventListener("visibilitychange", () => {
            if (document.hidden) {
                clearScheduledRefresh();
                setSyncState("paused", "Tab is hidden. Live sync will resume when you return.");
                return;
            }
            setSyncState("syncing", "Tab is active again. Pulling the latest live activity.");
            refreshPayload({ silent: false });
        });
        window.addEventListener("focus", () => {
            if (!document.hidden) {
                refreshPayload({ silent: true });
            }
        });
        window.addEventListener("online", () => {
            setSyncState("syncing", "Connection restored. Updating live activity now.");
            refreshPayload({ silent: false });
        });
        window.addEventListener("offline", () => {
            clearScheduledRefresh();
            setSyncState("reconnecting", "Connection is unavailable. Live sync will continue when the network returns.");
        });
    }

    function bindPerformanceMonitoringPage() {
        const root = document.getElementById("heavenectionPerformanceMonitoringPage");
        if (!root) {
            return;
        }

        const apiUrl = root.dataset.apiUrl || window.heavenectionAdmin?.liveMonitoringUrl;
        const profileUrlTemplate = root.dataset.profileUrlTemplate || "";
        const graphWall = document.getElementById("performanceMonitoringGraphWall");
        const alertEngine = document.getElementById("performanceMonitoringAlertEngine");
        const timeline = document.getElementById("performanceMonitoringTimeline");
        const queueHeatmap = document.getElementById("performanceMonitoringQueueHeatmap");
        const outcomeFunnel = document.getElementById("performanceMonitoringOutcomeFunnel");
        const compareRoster = document.getElementById("performanceMonitoringCompareRoster");
        const compareDetail = document.getElementById("performanceMonitoringCompareDetail");
        const generatedAtNode = document.getElementById("performanceMonitoringGeneratedAt");
        const nextRefreshNode = document.getElementById("performanceMonitoringNextRefresh");
        const refreshButton = document.getElementById("performanceMonitoringRefreshButton");
        const syncBadge = document.getElementById("performanceMonitoringSyncBadge");
        const syncStateNode = document.getElementById("performanceMonitoringSyncState");
        const syncDetailNode = document.getElementById("performanceMonitoringSyncDetail");
        const liveStaffNode = document.getElementById("performanceMonitoringLiveStaff");
        const activeHoursNode = document.getElementById("performanceMonitoringActiveHours");
        const reviewPressureNode = document.getElementById("performanceMonitoringReviewPressure");
        const queueLoadNode = document.getElementById("performanceMonitoringQueueLoad");
        const convertedNode = document.getElementById("performanceMonitoringConverted");
        const refreshMs = 8000;
        let refreshTimer = null;
        let countdownTimer = null;
        let nextRefreshAt = null;
        let refreshInFlight = false;
        let latestPayload = readJsonScript("heavenectionPerformanceMonitoringPayload") || {};
        let latestStaffRows = Array.isArray(latestPayload?.staff_rows) ? latestPayload.staff_rows : [];
        const selectedStaffIds = new Set();

        function asNumber(value) {
            const parsed = Number(value || 0);
            return Number.isFinite(parsed) ? parsed : 0;
        }

        function parseDurationLabel(label) {
            const text = String(label || "").trim().toLowerCase();
            if (!text) {
                return 0;
            }
            let totalMinutes = 0;
            const hourMatch = text.match(/(\d+(?:\.\d+)?)\s*h/);
            const minuteMatch = text.match(/(\d+(?:\.\d+)?)\s*m/);
            const secondMatch = text.match(/(\d+(?:\.\d+)?)\s*s/);
            if (hourMatch) {
                totalMinutes += Number(hourMatch[1]) * 60;
            }
            if (minuteMatch) {
                totalMinutes += Number(minuteMatch[1]);
            }
            if (secondMatch) {
                totalMinutes += Number(secondMatch[1]) / 60;
            }
            if (!totalMinutes && /^\d+(?:\.\d+)?$/.test(text)) {
                totalMinutes = Number(text);
            }
            return Number.isFinite(totalMinutes) ? totalMinutes : 0;
        }

        function withTemplateId(urlTemplate, staffId) {
            if (!urlTemplate || !staffId) {
                return "#";
            }
            return urlTemplate.replace("00000000-0000-0000-0000-000000000000", staffId);
        }

        function profileUrlForRow(row) {
            return withTemplateId(profileUrlTemplate, String(row?.id || "").trim());
        }

        function clearScheduledRefresh() {
            if (refreshTimer) {
                window.clearTimeout(refreshTimer);
                refreshTimer = null;
            }
            if (countdownTimer) {
                window.clearInterval(countdownTimer);
                countdownTimer = null;
            }
        }

        function startCountdown() {
            if (!nextRefreshNode) {
                return;
            }
            if (countdownTimer) {
                window.clearInterval(countdownTimer);
            }
            countdownTimer = window.setInterval(() => {
                if (!nextRefreshAt) {
                    nextRefreshNode.textContent = "--";
                    return;
                }
                const seconds = Math.max(0, Math.ceil((nextRefreshAt - Date.now()) / 1000));
                nextRefreshNode.textContent = `${seconds}s`;
            }, 250);
        }

        function scheduleRefresh() {
            clearScheduledRefresh();
            nextRefreshAt = Date.now() + refreshMs;
            startCountdown();
            refreshTimer = window.setTimeout(() => {
                refreshPayload({ silent: true });
            }, refreshMs);
        }

        function setSyncState(state, detail) {
            if (syncBadge) {
                syncBadge.classList.remove("is-live", "is-warning", "is-danger");
                if (state === "error") {
                    syncBadge.classList.add("is-danger");
                } else if (state === "syncing") {
                    syncBadge.classList.add("is-warning");
                } else {
                    syncBadge.classList.add("is-live");
                }
            }
            if (syncStateNode) {
                syncStateNode.textContent = state === "error"
                    ? "Sync Paused"
                    : state === "syncing"
                        ? "Refreshing Performance"
                        : "Live Sync Active";
            }
            if (syncDetailNode) {
                syncDetailNode.textContent = detail || "";
            }
        }

        function buildPerformanceScore(row) {
            const calls = asNumber(row?.calls_today);
            const quality = asNumber(row?.quality_score);
            const converted = asNumber(row?.converted_today);
            const assigned = asNumber(row?.assigned_leads);
            const workMinutes = parseDurationLabel(row?.active_hours_today);
            return (calls * 1.7) + (quality * 0.85) + (converted * 8) + (workMinutes * 0.42) + Math.min(assigned, 16);
        }

        function buildRiskScore(row) {
            const suspicious = asNumber(row?.suspicious_block_count);
            const zeroOnly = asNumber(row?.zero_only_block_count);
            const invalidShort = asNumber(row?.invalid_short_count);
            const missed = asNumber(row?.missed_callbacks);
            const reviewNeed = row?.needs_review ? 12 : 0;
            return (suspicious * 9) + (zeroOnly * 7) + (invalidShort * 5) + (missed * 4) + reviewNeed;
        }

        function qualityFactorRows(row) {
            const factors = [];
            const consistency = String(row?.outcome_consistency_label || "--").trim();
            if (consistency && consistency !== "--") {
                factors.push(`Consistency: ${consistency}`);
            }
            factors.push(`Real calls: ${asNumber(row?.real_call_count)}/${asNumber(row?.verified_attempt_count)}`);
            if (asNumber(row?.zero_only_block_count) > 0) {
                factors.push(`Zero-talk blocks: ${asNumber(row?.zero_only_block_count)}`);
            }
            if (asNumber(row?.suspicious_block_count) > 0) {
                factors.push(`Call review blocks: ${asNumber(row?.suspicious_block_count)}`);
            }
            if (asNumber(row?.invalid_short_count) > 0) {
                factors.push(`Invalid short: ${asNumber(row?.invalid_short_count)}`);
            }
            if (asNumber(row?.zero_second_attempt_count) > 0) {
                factors.push(`Zero-second attempts: ${asNumber(row?.zero_second_attempt_count)}`);
            }
            if (asNumber(row?.missed_callbacks) > 0) {
                factors.push(`Missed follow-up: ${asNumber(row?.missed_callbacks)}`);
            }
            if (asNumber(row?.long_away_count) > 0) {
                factors.push(`Long away periods: ${asNumber(row?.long_away_count)}`);
            }
            return factors;
        }

        function summarizeTeam(payload) {
            const summary = payload?.summary || {};
            if (liveStaffNode) {
                liveStaffNode.textContent = summary.online_now ?? 0;
            }
            if (activeHoursNode) {
                activeHoursNode.textContent = summary.active_hours_label || "0m";
            }
            if (reviewPressureNode) {
                reviewPressureNode.textContent = summary.review_needed_now ?? 0;
            }
            if (queueLoadNode) {
                queueLoadNode.textContent = summary.total_assigned ?? 0;
            }
            if (convertedNode) {
                convertedNode.textContent = summary.total_converted_today ?? 0;
            }
            if (generatedAtNode) {
                generatedAtNode.textContent = payload?.generated_at_label || "--";
            }
        }

        function renderGraphWall(rows) {
            if (!graphWall) {
                return;
            }
            if (!rows.length) {
                graphWall.innerHTML = '<div class="hc-work-review-empty-note">No worked staff found for today.</div>';
                return;
            }
            const ranked = rows
                .map((row) => ({
                    ...row,
                    performanceScore: buildPerformanceScore(row),
                }))
                .sort((left, right) => right.performanceScore - left.performanceScore)
                .slice(0, 8);
            const maxScore = Math.max(...ranked.map((row) => row.performanceScore), 1);
            graphWall.innerHTML = ranked.map((row, index) => {
                const width = Math.max(12, Math.round((row.performanceScore / maxScore) * 100));
                const profileUrl = profileUrlForRow(row);
                return `
                    <article class="hc-performance-graph-card ${index === 0 ? "is-leading" : ""}">
                        <div class="hc-performance-graph-head">
                            <div>
                                <strong>${escapeHtml(row.name || "Staff")}</strong>
                                <span>${escapeHtml(row.online_label || row.status_note || "Tracking")}</span>
                            </div>
                            <a class="btn btn-outline-light btn-sm" href="${escapeHtml(profileUrl)}">Open Profile</a>
                        </div>
                        <div class="hc-performance-graph-meter">
                            <span class="hc-performance-graph-fill" style="width:${width}%"></span>
                        </div>
                        <div class="hc-performance-graph-stats">
                            <span><strong>${asNumber(row.calls_today)}</strong> calls</span>
                            <span><strong>${escapeHtml(row.active_hours_today || "0m")}</strong> work</span>
                            <span><strong>${asNumber(row.quality_score)}</strong> quality</span>
                            <span><strong>${asNumber(row.converted_today)}</strong> converted</span>
                        </div>
                        <div class="hc-performance-alert-meta">
                            ${qualityFactorRows(row).slice(0, 3).map((factor) => `<span>${escapeHtml(factor)}</span>`).join("")}
                        </div>
                    </article>
                `;
            }).join("");
        }

        function renderAlertEngine(rows) {
            if (!alertEngine) {
                return;
            }
            const flagged = rows
                .map((row) => ({
                    ...row,
                    riskScore: buildRiskScore(row),
                }))
                .filter((row) => row.riskScore > 0)
                .sort((left, right) => right.riskScore - left.riskScore)
                .slice(0, 8);
            if (!flagged.length) {
                alertEngine.innerHTML = '<div class="hc-work-review-empty-note">No active review pressure right now. The team looks steady.</div>';
                return;
            }
            alertEngine.innerHTML = flagged.map((row) => `
                <article class="hc-performance-alert-card">
                    <div class="hc-performance-alert-top">
                        <div>
                            <strong>${escapeHtml(row.name || "Staff")}</strong>
                            <span>${escapeHtml(row.quality_label || "Monitoring")}</span>
                        </div>
                        <em>${row.riskScore}</em>
                    </div>
                    <p>${escapeHtml(row.quality_note || row.status_note || "Review this staff activity for unusual performance pressure.")}</p>
                    <div class="hc-performance-alert-meta">
                        <span>${asNumber(row.suspicious_block_count)} suspicious</span>
                        <span>${asNumber(row.zero_only_block_count)} zero blocks</span>
                        <span>${asNumber(row.invalid_short_count)} invalid short</span>
                        <span>${asNumber(row.missed_callbacks)} missed follow-up</span>
                    </div>
                    <div class="hc-performance-alert-meta">
                        ${qualityFactorRows(row).map((factor) => `<span>${escapeHtml(factor)}</span>`).join("")}
                    </div>
                </article>
            `).join("");
        }

        function renderTimeline(rows) {
            if (!timeline) {
                return;
            }
            if (!rows.length) {
                timeline.innerHTML = '<div class="hc-work-review-empty-note">No daily rhythm available yet.</div>';
                return;
            }
            const ranked = rows
                .map((row) => ({
                    ...row,
                    workMinutes: parseDurationLabel(row.active_hours_today),
                }))
                .sort((left, right) => buildPerformanceScore(right) - buildPerformanceScore(left))
                .slice(0, 10);
            const maxCalls = Math.max(...ranked.map((row) => asNumber(row.calls_today)), 1);
            const maxWork = Math.max(...ranked.map((row) => row.workMinutes), 1);
            const maxQuality = Math.max(...ranked.map((row) => asNumber(row.quality_score)), 1);
            timeline.innerHTML = ranked.map((row) => `
                <article class="hc-performance-lane">
                    <div class="hc-performance-lane-head">
                        <strong>${escapeHtml(row.name || "Staff")}</strong>
                        <span>${escapeHtml(row.active_hours_today || "0m")} tracked</span>
                    </div>
                    <div class="hc-performance-lane-bars">
                        <div class="hc-performance-lane-track is-calls"><span style="width:${Math.max(8, Math.round((asNumber(row.calls_today) / maxCalls) * 100))}%"></span></div>
                        <div class="hc-performance-lane-track is-work"><span style="width:${Math.max(8, Math.round((row.workMinutes / maxWork) * 100))}%"></span></div>
                        <div class="hc-performance-lane-track is-quality"><span style="width:${Math.max(8, Math.round((asNumber(row.quality_score) / maxQuality) * 100))}%"></span></div>
                    </div>
                    <div class="hc-performance-lane-meta">
                        <span>${asNumber(row.calls_today)} calls</span>
                        <span>${asNumber(row.assigned_leads)} queue</span>
                        <span>${asNumber(row.converted_today)} converted</span>
                    </div>
                </article>
            `).join("");
        }

        function renderQueueHeatmap(rows) {
            if (!queueHeatmap) {
                return;
            }
            if (!rows.length) {
                queueHeatmap.innerHTML = '<div class="hc-work-review-empty-note">No queue data available yet.</div>';
                return;
            }
            const ranked = rows
                .slice()
                .sort((left, right) => asNumber(right.assigned_leads) - asNumber(left.assigned_leads))
                .slice(0, 12);
            const maxQueue = Math.max(...ranked.map((row) => asNumber(row.assigned_leads)), 1);
            queueHeatmap.innerHTML = ranked.map((row) => {
                const load = asNumber(row.assigned_leads);
                const heat = Math.round((load / maxQueue) * 100);
                return `
                    <article class="hc-performance-heat-card">
                        <header>
                            <strong>${escapeHtml(row.name || "Staff")}</strong>
                            <span>${load} leads</span>
                        </header>
                        <div class="hc-performance-heat-bar"><span style="width:${Math.max(10, heat)}%"></span></div>
                        <footer>
                            <small>${escapeHtml(row.online_label || "Tracked")}</small>
                            <small>${asNumber(row.calls_today)} calls today</small>
                        </footer>
                    </article>
                `;
            }).join("");
        }

        function renderOutcomeFunnel(payload) {
            if (!outcomeFunnel) {
                return;
            }
            const summary = payload?.summary || {};
            const stages = [
                ["Active Staff", summary.total_staff ?? 0],
                ["Online Now", summary.online_now ?? 0],
                ["On Call", summary.on_call_now ?? 0],
                ["Calls Today", summary.total_calls_today ?? 0],
                ["Queue Load", summary.total_assigned ?? 0],
                ["Converted", summary.total_converted_today ?? 0],
            ];
            const maxValue = Math.max(...stages.map((stage) => asNumber(stage[1])), 1);
            outcomeFunnel.innerHTML = stages.map(([label, value]) => {
                const numericValue = asNumber(value);
                return `
                    <article class="hc-performance-funnel-step">
                        <div class="hc-performance-funnel-copy">
                            <span>${escapeHtml(label)}</span>
                            <strong>${numericValue}</strong>
                        </div>
                        <div class="hc-performance-funnel-bar"><span style="width:${Math.max(8, Math.round((numericValue / maxValue) * 100))}%"></span></div>
                    </article>
                `;
            }).join("");
        }

        function renderCompareRoster(rows) {
            if (!compareRoster) {
                return;
            }
            if (!rows.length) {
                compareRoster.innerHTML = '<div class="hc-work-review-empty-note">No staff available for comparison.</div>';
                return;
            }
            const ranked = rows
                .slice()
                .sort((left, right) => buildPerformanceScore(right) - buildPerformanceScore(left))
                .slice(0, 18);
            compareRoster.innerHTML = ranked.map((row) => {
                const selected = selectedStaffIds.has(String(row.id || ""));
                return `
                    <button type="button" class="hc-performance-compare-chip ${selected ? "is-selected" : ""}" data-compare-staff="${escapeHtml(String(row.id || ""))}">
                        <strong>${escapeHtml(row.name || "Staff")}</strong>
                        <span>${asNumber(row.calls_today)} calls · ${escapeHtml(row.active_hours_today || "0m")}</span>
                    </button>
                `;
            }).join("");
        }

        function renderCompareDetail(rows) {
            if (!compareDetail) {
                return;
            }
            const selectedRows = rows.filter((row) => selectedStaffIds.has(String(row.id || ""))).slice(0, 4);
            if (!selectedRows.length) {
                compareDetail.innerHTML = '<div class="hc-work-review-empty-note">Select up to four staff members to compare their live performance.</div>';
                return;
            }
            compareDetail.innerHTML = `
                <div class="hc-performance-compare-grid">
                    ${selectedRows.map((row) => `
                        <article class="hc-performance-compare-card">
                            <div class="hc-performance-compare-head">
                                <div>
                                    <strong>${escapeHtml(row.name || "Staff")}</strong>
                                    <span>${escapeHtml(row.online_label || row.status_note || "Tracking")}</span>
                                </div>
                                <a href="${escapeHtml(profileUrlForRow(row))}" class="btn btn-outline-light btn-sm">Profile</a>
                            </div>
                            <dl class="hc-performance-compare-metrics">
                                <div><dt>Calls</dt><dd>${asNumber(row.calls_today)}</dd></div>
                                <div><dt>Work</dt><dd>${escapeHtml(row.active_hours_today || "0m")}</dd></div>
                                <div><dt>Quality</dt><dd>${asNumber(row.quality_score)}</dd></div>
                                <div><dt>Queue</dt><dd>${asNumber(row.assigned_leads)}</dd></div>
                                <div><dt>Converted</dt><dd>${asNumber(row.converted_today)}</dd></div>
                                <div><dt>Real Calls</dt><dd>${asNumber(row.real_call_count)}</dd></div>
                            </dl>
                            <div class="hc-performance-alert-meta">
                                ${qualityFactorRows(row).map((factor) => `<span>${escapeHtml(factor)}</span>`).join("")}
                            </div>
                        </article>
                    `).join("")}
                </div>
            `;
        }

        function renderPayload(payload) {
            latestPayload = payload || {};
            latestStaffRows = Array.isArray(latestPayload?.staff_rows) ? latestPayload.staff_rows : [];
            for (const selectedId of Array.from(selectedStaffIds)) {
                if (!latestStaffRows.some((row) => String(row?.id || "") === selectedId)) {
                    selectedStaffIds.delete(selectedId);
                }
            }
            summarizeTeam(latestPayload);
            renderGraphWall(latestStaffRows);
            renderAlertEngine(latestStaffRows);
            renderTimeline(latestStaffRows);
            renderQueueHeatmap(latestStaffRows);
            renderOutcomeFunnel(latestPayload);
            renderCompareRoster(latestStaffRows);
            renderCompareDetail(latestStaffRows);
        }

        async function refreshPayload(options = {}) {
            if (!apiUrl || refreshInFlight) {
                return;
            }
            refreshInFlight = true;
            setSyncState("syncing", options.silent ? "Refreshing live performance signals quietly in the background." : "Pulling the latest performance activity right now.");
            try {
                const payload = await requestJson(apiUrl, { method: "GET" });
                renderPayload(payload);
                setSyncState("live", "Performance board is synced and listening for the next refresh.");
                scheduleRefresh();
            } catch (error) {
                setSyncState("error", error.message || "Performance board could not refresh right now.");
                clearScheduledRefresh();
            } finally {
                refreshInFlight = false;
            }
        }

        compareRoster?.addEventListener("click", (event) => {
            const button = event.target.closest("[data-compare-staff]");
            if (!button) {
                return;
            }
            const staffId = String(button.dataset.compareStaff || "").trim();
            if (!staffId) {
                return;
            }
            if (selectedStaffIds.has(staffId)) {
                selectedStaffIds.delete(staffId);
            } else {
                if (selectedStaffIds.size >= 4) {
                    const firstSelected = selectedStaffIds.values().next().value;
                    if (firstSelected) {
                        selectedStaffIds.delete(firstSelected);
                    }
                }
                selectedStaffIds.add(staffId);
            }
            renderCompareRoster(latestStaffRows);
            renderCompareDetail(latestStaffRows);
        });

        refreshButton?.addEventListener("click", () => {
            refreshPayload({ silent: false });
        });

        document.addEventListener("visibilitychange", () => {
            if (document.hidden) {
                clearScheduledRefresh();
                setSyncState("syncing", "Performance board paused while this tab is hidden.");
                return;
            }
            refreshPayload({ silent: true });
        });

        window.addEventListener("focus", () => {
            if (!document.hidden) {
                refreshPayload({ silent: true });
            }
        });

        window.addEventListener("online", () => {
            refreshPayload({ silent: false });
        });

        window.addEventListener("offline", () => {
            clearScheduledRefresh();
            setSyncState("error", "Network unavailable. Performance board will resume when the connection returns.");
        });

        renderPayload(latestPayload);
        scheduleRefresh();
    }

    function bindAdminAlertCenter() {
        const button = document.getElementById("heavenectionAdminAlertButton");
        const badge = document.getElementById("heavenectionAdminAlertBadge");
        const statusNode = document.getElementById("heavenectionAdminAlertStatus");
        const generatedAtNode = document.getElementById("heavenectionAdminAlertGeneratedAt");
        const listNode = document.getElementById("heavenectionAdminAlertList");
        const flashTarget = document.getElementById("heavenectionClientFlash");
        const permissionButton = document.getElementById("heavenectionAdminAlertPermissionButton");
        const permissionNote = document.getElementById("heavenectionAdminAlertPermissionNote");
        const soundToggle = document.getElementById("heavenectionAdminAlertSoundToggle");
        const apiUrl = window.heavenectionAdmin?.adminAlertsUrl || "";
        const notificationIconUrl = window.heavenectionAdmin?.notificationIconUrl || "";
        if (!button || !listNode) {
            return;
        }

        let latestPayload = readJsonScript("heavenectionAdminAlertPayload") || { summary: {}, alerts: [] };
        let refreshTimer = null;
        let lastAlertSignature = "";
        const refreshMs = 15000;
        const soundPreferenceKey = "heavenectionAdminAlertSoundEnabled";
        const shownFlashIdsKey = "heavenectionAdminAlertShownFlashIds";
        const shownDesktopIdsKey = "heavenectionAdminAlertShownDesktopIds";
        const seenAlertIdsKey = "heavenectionAdminAlertSeenIds";

        function readStoredIdSet(storageKey) {
            if (!window.sessionStorage) {
                return new Set();
            }
            try {
                const raw = window.sessionStorage.getItem(storageKey);
                if (!raw) {
                    return new Set();
                }
                const values = JSON.parse(raw);
                if (!Array.isArray(values)) {
                    return new Set();
                }
                return new Set(values.map((value) => String(value || "").trim()).filter(Boolean));
            } catch (error) {
                return new Set();
            }
        }

        function writeStoredIdSet(storageKey, values) {
            if (!window.sessionStorage) {
                return;
            }
            try {
                window.sessionStorage.setItem(storageKey, JSON.stringify(Array.from(values)));
            } catch (error) {
                // Ignore storage write failures.
            }
        }

        const shownFlashIds = readStoredIdSet(shownFlashIdsKey);
        const shownDesktopIds = readStoredIdSet(shownDesktopIdsKey);
        const seenAlertIds = readStoredIdSet(seenAlertIdsKey);

        function markAlertSeen(alertId) {
            const normalizedId = String(alertId || "").trim();
            if (!normalizedId) {
                return;
            }
            seenAlertIds.add(normalizedId);
            writeStoredIdSet(seenAlertIdsKey, seenAlertIds);
        }

        function isAlertSeen(alertId) {
            const normalizedId = String(alertId || "").trim();
            return normalizedId ? seenAlertIds.has(normalizedId) : false;
        }

        function isNotificationSupported() {
            return typeof window.Notification !== "undefined";
        }

        function isSoundEnabled() {
            if (!window.localStorage) {
                return false;
            }
            return window.localStorage.getItem(soundPreferenceKey) === "1";
        }

        function setSoundEnabled(enabled) {
            if (!window.localStorage) {
                return;
            }
            window.localStorage.setItem(soundPreferenceKey, enabled ? "1" : "0");
        }

        function syncNotificationControls() {
            const supported = isNotificationSupported();
            const permission = supported ? window.Notification.permission : "unsupported";
            if (permissionButton) {
                permissionButton.hidden = !supported || permission === "granted";
                permissionButton.disabled = permission === "denied";
                permissionButton.textContent = permission === "denied"
                    ? "Browser Alerts Blocked"
                    : "Enable Browser Alerts";
            }
            if (permissionNote) {
                permissionNote.classList.remove("is-granted", "is-denied");
                if (!supported) {
                    permissionNote.textContent = "This browser does not support desktop notifications.";
                } else if (permission === "granted") {
                    permissionNote.classList.add("is-granted");
                    permissionNote.textContent = "Browser notifications are enabled. New warning and critical alerts can appear as desktop notifications.";
                } else if (permission === "denied") {
                    permissionNote.classList.add("is-denied");
                    permissionNote.textContent = "Browser notifications are blocked. Allow notifications in browser settings to receive desktop alerts.";
                } else {
                    permissionNote.textContent = "Browser notifications are not enabled yet.";
                }
            }
            if (soundToggle) {
                soundToggle.checked = isSoundEnabled();
            }
        }

        function alertToneClass(severity) {
            if (severity === "critical") {
                return "danger";
            }
            if (severity === "warning") {
                return "warning";
            }
            if (severity === "good") {
                return "success";
            }
            return "primary";
        }

        function playAlertSound(severity) {
            if (!isSoundEnabled()) {
                return;
            }
            const AudioContextClass = window.AudioContext || window.webkitAudioContext;
            if (!AudioContextClass) {
                return;
            }
            try {
                const audioContext = new AudioContextClass();
                const oscillator = audioContext.createOscillator();
                const gainNode = audioContext.createGain();
                oscillator.type = "sine";
                oscillator.frequency.value = severity === "critical" ? 880 : 660;
                gainNode.gain.setValueAtTime(0.0001, audioContext.currentTime);
                gainNode.gain.exponentialRampToValueAtTime(0.08, audioContext.currentTime + 0.02);
                gainNode.gain.exponentialRampToValueAtTime(0.0001, audioContext.currentTime + 0.32);
                oscillator.connect(gainNode);
                gainNode.connect(audioContext.destination);
                oscillator.start();
                oscillator.stop(audioContext.currentTime + 0.34);
                oscillator.onended = () => {
                    audioContext.close().catch(() => {});
                };
            } catch (error) {
                // Ignore sound playback failures quietly.
            }
        }

        function resolveAdminAlertUrl(targetUrl) {
            const raw = String(targetUrl || "").trim();
            if (!raw) {
                return "";
            }
            try {
                return new URL(raw, window.location.origin).href;
            } catch (error) {
                return raw;
            }
        }

        function openAdminAlertTarget(targetUrl, alertId = "") {
            markAlertSeen(alertId);
            const resolvedUrl = resolveAdminAlertUrl(targetUrl);
            if (!resolvedUrl) {
                return;
            }
            try {
                const opened = window.open(resolvedUrl, "_self");
                if (opened) {
                    return;
                }
            } catch (error) {
                // Fall back to direct navigation below.
            }
            window.location.assign(resolvedUrl);
        }

        function showDesktopNotification(alert) {
            if (!alert?.id || shownDesktopIds.has(alert.id)) {
                return;
            }
            if (!isNotificationSupported() || window.Notification.permission !== "granted") {
                return;
            }
            shownDesktopIds.add(alert.id);
            writeStoredIdSet(shownDesktopIdsKey, shownDesktopIds);
            const notification = new window.Notification(alert.title || "Admin Alert", {
                body: alert.message || "",
                tag: `heavenection-admin-alert-${alert.id}`,
                icon: notificationIconUrl || undefined,
                requireInteraction: alert.severity === "critical",
            });
            notification.onclick = () => {
                try {
                    window.focus();
                } catch (error) {
                    // Ignore focus issues.
                }
                if (alert.target_url) {
                    openAdminAlertTarget(alert.target_url, alert.id);
                }
                notification.close();
            };
            window.setTimeout(() => notification.close(), alert.severity === "critical" ? 15000 : 9000);
            playAlertSound(alert.severity);
        }

        function renderFlashAlert(alert) {
            if (!flashTarget || !alert?.id || shownFlashIds.has(alert.id)) {
                return;
            }
            shownFlashIds.add(alert.id);
            writeStoredIdSet(shownFlashIdsKey, shownFlashIds);
            const toneClass = alertToneClass(alert.severity);
            const stack = flashTarget.querySelector(".hc-page-flash-stack") || (() => {
                const wrapper = document.createElement("div");
                wrapper.className = "hc-page-flash-stack";
                flashTarget.prepend(wrapper);
                return wrapper;
            })();
            const node = document.createElement("div");
            node.className = `alert alert-${toneClass} alert-dismissible fade show`;
            node.setAttribute("role", "alert");
            node.innerHTML = `
                <strong>${escapeHtml(alert.title || "Alert")}</strong>
                <span class="ms-1">${escapeHtml(alert.message || "")}</span>
                ${alert.target_url ? `<a href="${escapeHtml(alert.target_url)}" class="alert-link ms-2">${escapeHtml(alert.target_label || "Open")}</a>` : ""}
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
            `;
            stack.prepend(node);
            window.setTimeout(() => {
                if (node && node.parentNode) {
                    node.remove();
                }
            }, alert.severity === "critical" ? 12000 : 8000);
        }

        function renderPayload(payload) {
            latestPayload = payload || { summary: {}, alerts: [] };
            const summary = latestPayload.summary || {};
            const alerts = Array.isArray(latestPayload.alerts) ? latestPayload.alerts : [];
            const severityOrder = { critical: 0, warning: 1, normal: 2, good: 3 };
            const orderedAlerts = alerts
                .slice()
                .sort((left, right) => {
                    const leftSeen = isAlertSeen(left?.id);
                    const rightSeen = isAlertSeen(right?.id);
                    if (leftSeen !== rightSeen) {
                        return leftSeen ? 1 : -1;
                    }
                    const leftSeverity = severityOrder[String(left?.severity || "").toLowerCase()] ?? 99;
                    const rightSeverity = severityOrder[String(right?.severity || "").toLowerCase()] ?? 99;
                    if (leftSeverity !== rightSeverity) {
                        return leftSeverity - rightSeverity;
                    }
                    const leftScore = Number(left?.sort_score || 0);
                    const rightScore = Number(right?.sort_score || 0);
                    if (leftScore !== rightScore) {
                        return rightScore - leftScore;
                    }
                    return String(right?.id || "").localeCompare(String(left?.id || ""));
                });
            const totalAlerts = Number(summary.total_alerts || orderedAlerts.length || 0);
            const unreadAlerts = orderedAlerts.filter((alert) => !isAlertSeen(alert.id));
            const unreadCount = unreadAlerts.length;
            const criticalAlerts = Number(summary.critical_alerts || 0);

            if (badge) {
                badge.textContent = String(unreadCount);
                badge.classList.toggle("d-none", unreadCount <= 0);
            }
            if (statusNode) {
                statusNode.textContent = totalAlerts <= 0
                    ? "No active alerts"
                    : unreadCount > 0
                        ? `${unreadCount} unopened alert${unreadCount === 1 ? "" : "s"}`
                        : "All active alerts opened";
            }
            if (generatedAtNode) {
                generatedAtNode.textContent = summary.generated_at_label || "--";
            }

            listNode.innerHTML = orderedAlerts.length
                ? orderedAlerts.map((alert) => `
                    <article class="hc-admin-alert-item is-${escapeHtml(alert.severity || "normal")}${isAlertSeen(alert.id) ? " is-read" : ""}" data-alert-id="${escapeHtml(alert.id || "")}">
                        <div class="hc-admin-alert-item-head">
                            <span class="hc-admin-alert-chip is-${escapeHtml(alert.severity || "normal")}">${escapeHtml(alert.severity_label || "Normal")}</span>
                            <small>${escapeHtml(alert.meta_label || "")}</small>
                        </div>
                        <strong>${escapeHtml(alert.title || "Alert")}</strong>
                        <p>${escapeHtml(alert.message || "")}</p>
                        ${alert.target_url ? `<a href="${escapeHtml(alert.target_url)}" class="btn btn-sm btn-outline-primary hc-admin-alert-open-link" data-alert-open="1" data-alert-id="${escapeHtml(alert.id || "")}">${escapeHtml(alert.target_label || "Open")}</a>` : ""}
                    </article>
                `).join("")
                : '<div class="hc-admin-alert-empty">No alert signals are active right now.</div>';

            button.classList.toggle("btn-outline-danger", criticalAlerts > 0);
            button.classList.toggle("btn-outline-primary", criticalAlerts <= 0);
            syncNotificationControls();
        }

        async function refreshPayload(options = {}) {
            if (!apiUrl) {
                return;
            }
            try {
                const payload = await requestJson(apiUrl, { method: "GET" });
                renderPayload(payload);
                const signature = JSON.stringify((payload.alerts || []).map((alert) => [alert.id, alert.severity]));
                if (signature !== lastAlertSignature) {
                    (payload.alerts || [])
                        .filter((alert) => alert.severity === "critical" || alert.severity === "warning")
                        .slice(0, 3)
                        .forEach((alert) => {
                            renderFlashAlert(alert);
                            showDesktopNotification(alert);
                        });
                }
                lastAlertSignature = signature;
            } catch (error) {
                if (!options.silent && statusNode) {
                    statusNode.textContent = "Alert refresh delayed";
                }
            } finally {
                if (refreshTimer) {
                    window.clearTimeout(refreshTimer);
                }
                refreshTimer = window.setTimeout(() => refreshPayload({ silent: true }), refreshMs);
            }
        }

        renderPayload(latestPayload);
        lastAlertSignature = JSON.stringify((latestPayload.alerts || []).map((alert) => [alert.id, alert.severity]));
        refreshPayload({ silent: true });
        syncNotificationControls();

        permissionButton?.addEventListener("click", async () => {
            if (!isNotificationSupported()) {
                syncNotificationControls();
                return;
            }
            try {
                await window.Notification.requestPermission();
            } catch (error) {
                // Ignore permission request failures.
            }
            syncNotificationControls();
        });

        soundToggle?.addEventListener("change", () => {
            setSoundEnabled(Boolean(soundToggle.checked));
            syncNotificationControls();
        });

        listNode.addEventListener("click", (event) => {
            const openLink = event.target.closest("a[data-alert-open='1']");
            if (!openLink) {
                return;
            }
            const href = openLink.getAttribute("href");
            if (!href) {
                return;
            }
            event.preventDefault();
            openAdminAlertTarget(href, openLink.dataset.alertId || "");
            renderPayload(latestPayload);
        });

        window.addEventListener("focus", () => refreshPayload({ silent: true }));
        window.addEventListener("online", () => refreshPayload({ silent: false }));
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
    bindPerformanceMonitoringPage();
    bindAdminAlertCenter();
    bindSidebarSections();
    bindEmiCalculator();
})();
