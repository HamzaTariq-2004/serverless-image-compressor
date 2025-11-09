// script.js
// Configuration
const API_ENDPOINT = 'API_Gateway_ENDPOINT'; // Replace with  API Gateway endpoint
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

// DOM Elements
const uploadForm = document.getElementById('uploadForm');
const emailInput = document.getElementById('email');
const qualitySelect = document.getElementById('quality');
const imageFileInput = document.getElementById('imageFile');
const fileLabel = document.getElementById('fileLabel');
const filePreview = document.getElementById('filePreview');
const submitBtn = document.getElementById('submitBtn');

const progressSection = document.getElementById('progressSection');
const progressText = document.getElementById('progressText');
const progressFill = document.getElementById('progressFill');

const successSection = document.getElementById('successSection');
const successEmail = document.getElementById('successEmail');
const uploadAnotherBtn = document.getElementById('uploadAnotherBtn');

const errorSection = document.getElementById('errorSection');
const errorText = document.getElementById('errorText');
const retryBtn = document.getElementById('retryBtn');

// State
let selectedFile = null;

// Quality mapping
const qualityMapping = {
    'high': 80,
    'medium': 60,
    'low': 40
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
    setupDragAndDrop();
});

// Setup event listeners
function setupEventListeners() {
    uploadForm.addEventListener('submit', handleFormSubmit);
    imageFileInput.addEventListener('change', handleFileSelect);
    uploadAnotherBtn.addEventListener('click', resetForm);
    retryBtn.addEventListener('click', resetForm);
}

// Setup drag and drop
function setupDragAndDrop() {
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        fileLabel.addEventListener(eventName, preventDefaults, false);
    });

    ['dragenter', 'dragover'].forEach(eventName => {
        fileLabel.addEventListener(eventName, () => {
            fileLabel.classList.add('drag-over');
        }, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
        fileLabel.addEventListener(eventName, () => {
            fileLabel.classList.remove('drag-over');
        }, false);
    });

    fileLabel.addEventListener('drop', handleDrop, false);
}

function preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
}

// Handle file drop
function handleDrop(e) {
    const dt = e.dataTransfer;
    const files = dt.files;

    if (files.length > 0) {
        imageFileInput.files = files;
        handleFileSelect({ target: { files: files } });
    }
}

// Handle file selection
function handleFileSelect(e) {
    const file = e.target.files[0];

    if (!file) {
        selectedFile = null;
        filePreview.classList.remove('active');
        return;
    }

    // Validate file type
    const validTypes = ['image/png', 'image/jpeg', 'image/jpg'];
    if (!validTypes.includes(file.type)) {
        showError('Please select a valid image file (PNG, JPG, or JPEG)');
        imageFileInput.value = '';
        selectedFile = null;
        filePreview.classList.remove('active');
        return;
    }

    // Validate file size
    if (file.size > MAX_FILE_SIZE) {
        showError('File size must be less than 10MB');
        imageFileInput.value = '';
        selectedFile = null;
        filePreview.classList.remove('active');
        return;
    }

    selectedFile = file;
    displayFilePreview(file);
}

// Display file preview
function displayFilePreview(file) {
    const reader = new FileReader();

    reader.onload = (e) => {
        const fileSize = formatFileSize(file.size);
        
        filePreview.innerHTML = `
            <img src="${e.target.result}" alt="Preview" class="file-preview-image">
            <div class="file-preview-info">
                <div class="file-preview-name">${file.name}</div>
                <div class="file-preview-size">${fileSize}</div>
            </div>
            <button type="button" class="file-preview-remove" onclick="removeFile()">Remove</button>
        `;
        
        filePreview.classList.add('active');
    };

    reader.readAsDataURL(file);
}

// Remove file
function removeFile() {
    imageFileInput.value = '';
    selectedFile = null;
    filePreview.classList.remove('active');
    filePreview.innerHTML = '';
}

// Format file size
function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

// Handle form submission
async function handleFormSubmit(e) {
    e.preventDefault();

    // Validate form
    if (!validateForm()) {
        return;
    }

    // Show progress
    showProgress();

    try {
        // Step 1: Get presigned URL
        updateProgress('Getting upload URL...', 20);
        const presignedData = await getPresignedUrl();

        // Step 2: Upload to S3
        updateProgress('Uploading image...', 40);
        await uploadToS3(presignedData);

        // Step 3: Show success
        updateProgress('Processing complete!', 100);
        setTimeout(() => {
            showSuccess();
        }, 500);

    } catch (error) {
        console.error('Upload error:', error);
        showError(error.message || 'Failed to upload image. Please try again.');
    }
}

// Validate form
function validateForm() {
    if (!emailInput.value.trim()) {
        showError('Please enter your email address');
        return false;
    }

    if (!isValidEmail(emailInput.value.trim())) {
        showError('Please enter a valid email address');
        return false;
    }

    if (!qualitySelect.value) {
        showError('Please select image quality');
        return false;
    }

    if (!selectedFile) {
        showError('Please select an image to upload');
        return false;
    }

    return true;
}

// Validate email
function isValidEmail(email) {
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return re.test(email);
}

// Get presigned URL from API Gateway
async function getPresignedUrl() {
    const email = emailInput.value.trim();
    const quality = qualityMapping[qualitySelect.value];
    const fileName = selectedFile.name;
    const fileType = selectedFile.type;

    const response = await fetch(`${API_ENDPOINT}/get-presigned-url`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            email: email,
            quality: quality,
            fileName: fileName,
            fileType: fileType
        })
    });

    if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.message || `HTTP error! status: ${response.status}`);
    }

    const data = await response.json();
    return data;
}

// Upload file to S3 using presigned URL
async function uploadToS3(presignedData) {
    const { uploadUrl, fields } = presignedData;

    const formData = new FormData();
    for (const [key, value] of Object.entries(fields)) {
        formData.append(key, value);
    }
    formData.append('file', selectedFile);

    console.log("Uploading to:", uploadUrl);
    console.log("Form fields:", fields);

    const response = await fetch(uploadUrl, {
        method: 'POST',
        body: formData,
        mode: 'cors', // ensure CORS mode
        credentials: 'omit'
    });

    if (!response.ok) {
        const errText = await response.text();
        console.error("S3 upload failed:", response.status, errText);
        throw new Error(`S3 upload failed: ${response.status}`);
    }

    return response;
}

// Show progress section
function showProgress() {
    uploadForm.style.display = 'none';
    successSection.style.display = 'none';
    errorSection.style.display = 'none';
    progressSection.style.display = 'block';
    submitBtn.disabled = true;
}

// Update progress
function updateProgress(message, percentage) {
    progressText.textContent = message;
    progressFill.style.width = percentage + '%';
}

// Show success section
function showSuccess() {
    progressSection.style.display = 'none';
    successSection.style.display = 'block';
    successEmail.textContent = emailInput.value.trim();
}

// Show error
function showError(message) {
    uploadForm.style.display = 'none';
    progressSection.style.display = 'none';
    successSection.style.display = 'none';
    errorSection.style.display = 'block';
    errorText.textContent = message;
    submitBtn.disabled = false;
}

// Reset form
function resetForm() {
    uploadForm.reset();
    removeFile();
    uploadForm.style.display = 'flex';
    progressSection.style.display = 'none';
    successSection.style.display = 'none';
    errorSection.style.display = 'none';
    submitBtn.disabled = false;
    progressFill.style.width = '0%';
}

// Make removeFile available globally
window.removeFile = removeFile;