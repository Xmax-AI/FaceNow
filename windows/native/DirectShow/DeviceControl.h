//
//  DeviceControl.h
//  FaceNow
//

#pragma once

bool DeviceExists(bool* nameCurrent = nullptr) {
    ComPtr<ICreateDevEnum> enumerator;
    Check(CoCreateInstance(CLSID_SystemDeviceEnum, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&enumerator)), "open DirectShow device enumerator");
    ComPtr<IEnumMoniker> devices;
    HRESULT result = enumerator->CreateClassEnumerator(CLSID_VideoInputDeviceCategory, &devices, 0);
    if (result == S_FALSE) return false;
    Check(result, "enumerate DirectShow cameras");

    ComPtr<IMoniker> device;
    while (devices->Next(1, device.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
        ComPtr<IPropertyBag> properties;
        if (FAILED(device->BindToStorage(nullptr, nullptr, IID_PPV_ARGS(&properties)))) continue;
        VARIANT value{};
        GUID id{};
        bool match = SUCCEEDED(properties->Read(L"CLSID", &value, nullptr)) && value.vt == VT_BSTR && value.bstrVal &&
            SUCCEEDED(CLSIDFromString(value.bstrVal, &id)) && id == DirectShowId;
        VariantClear(&value);
        if (!match) continue;
        if (nameCurrent) {
            *nameCurrent = SUCCEEDED(properties->Read(L"FriendlyName", &value, nullptr)) && value.vt == VT_BSTR && value.bstrVal &&
                std::wstring_view(value.bstrVal) == CameraName;
            VariantClear(&value);
        }
        return true;
    }
    return false;
}

bool HasRegistration() { return !InstalledSource().empty() || DeviceExists(); }

void Status() {
    auto path = InstalledSource();
    bool installed = !path.empty() && fs::is_regular_file(path);
    bool nameCurrent = false;
    bool registered = DeviceExists(&nameCurrent);
    std::wstring endpoint;
    if (registered) {
        DWORD session = 0;
        if (!ProcessIdToSessionId(GetCurrentProcessId(), &session))
            throw Failure{HRESULT_FROM_WIN32(GetLastError()), "resolve DirectShow camera session"};
        endpoint = DirectShowEndpoint(session);
    }
    std::cout << "{\"installed\":" << (installed ? "true" : "false")
        << ",\"current\":" << (installed && IsCurrentSource(path) ? "true" : "false")
        << ",\"registered\":" << (registered ? "true" : "false")
        << ",\"nameCurrent\":" << (nameCurrent ? "true" : "false")
        << ",\"symbolicLink\":" << Json(endpoint) << "}\n";
}

void CallRegistration(const fs::path& path, const char* operation) {
    HMODULE module = LoadLibraryExW(path.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) throw Failure{HRESULT_FROM_WIN32(GetLastError()), "load DirectShow camera DLL"};
    using Entry = HRESULT (STDAPICALLTYPE*)();
    auto entry = reinterpret_cast<Entry>(GetProcAddress(module, operation));
    HRESULT result = entry ? entry() : HRESULT_FROM_WIN32(GetLastError());
    FreeLibrary(module);
    Check(result, operation);
}

void Install() {
    auto previous = fs::path(InstalledSource());
    auto destination = DeploySource();
    try {
        CallRegistration(destination, "DllRegisterServer");
    } catch (...) {
        if (!previous.empty() && fs::is_regular_file(previous))
            CallRegistration(previous, "DllRegisterServer");
        throw;
    }
    std::cout << "{\"installed\":true}\n";
}

void Enable() {
    bool nameCurrent = false;
    if (!fs::is_regular_file(InstalledSource()) || !DeviceExists(&nameCurrent) || !nameCurrent)
        throw Failure{HRESULT_FROM_WIN32(ERROR_NOT_FOUND), "find the registered FaceNow DirectShow camera"};
    Status();
}

void RemoveInstalledDirectShow() {
    if (!HasRegistration()) return;
    // The packaged DLL can unregister a partial or damaged installation by its fixed class ID.
    CallRegistration(Directory() / SourceFile, "DllUnregisterServer");
    if (HasRegistration()) throw Failure{E_FAIL, "verify DirectShow camera removal"};
}

void Remove() {
    if (HasRegistration()) {
        if (IsUserAnAdmin()) {
            RemoveInstalledDirectShow();
        } else {
            auto executable = ExecutablePath();
            SHELLEXECUTEINFOW info{};
            info.cbSize = sizeof(info);
            info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
            info.lpVerb = L"runas";
            info.lpFile = executable.c_str();
            info.lpParameters = L"--remove-elevated";
            info.nShow = SW_HIDE;
            if (!ShellExecuteExW(&info)) throw Failure{HRESULT_FROM_WIN32(GetLastError()), "elevate DirectShow camera removal"};
            if (!info.hProcess) throw Failure{E_FAIL, "start elevated DirectShow camera removal"};
            DWORD exitCode = 0;
            bool removed = WaitForSingleObject(info.hProcess, INFINITE) == WAIT_OBJECT_0 &&
                GetExitCodeProcess(info.hProcess, &exitCode) && exitCode == 0;
            CloseHandle(info.hProcess);
            if (!removed) throw Failure{E_FAIL, "remove DirectShow camera"};
        }
    }
    Status();
}
