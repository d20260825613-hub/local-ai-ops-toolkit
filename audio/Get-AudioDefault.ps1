# Report the current default audio endpoints (render + capture) and every render
# endpoint's state, via the Core Audio (MMDevice) COM API.
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    int GetDevice(string id, out IMMDevice device);
    int RegisterEndpointNotificationCallback(IntPtr client);
    int UnregisterEndpointNotificationCallback(IntPtr client);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection {
    int GetCount(out int count);
    int Item(int index, out IMMDevice device);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    int OpenPropertyStore(int access, out IPropertyStore properties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    int GetState(out int state);
}

[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore {
    int GetCount(out int count);
    int GetAt(int index, out PROPERTYKEY key);
    int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
    int Commit();
}

[StructLayout(LayoutKind.Sequential)]
public struct PROPERTYKEY { public Guid fmtid; public int pid; }

[StructLayout(LayoutKind.Explicit)]
public struct PROPVARIANT {
    [FieldOffset(0)] public short vt;
    [FieldOffset(8)] public IntPtr pointerValue;
}

public static class AudioInfo {
    static PROPERTYKEY PKEY_Device_FriendlyName = new PROPERTYKEY {
        fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };

    static PROPERTYKEY PKEY_Device_DeviceDesc = new PROPERTYKEY {
        fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 2 };

    static string GetString(IPropertyStore store, PROPERTYKEY key) {
        PROPVARIANT v;
        if (store.GetValue(ref key, out v) != 0) return "";
        if (v.pointerValue == IntPtr.Zero) return "";
        return Marshal.PtrToStringUni(v.pointerValue) ?? "";
    }

    public static string Describe(IMMDevice dev) {
        string id;
        dev.GetId(out id);
        int state;
        dev.GetState(out state);
        IPropertyStore store;
        dev.OpenPropertyStore(0, out store);
        string name = GetString(store, PKEY_Device_FriendlyName);
        if (string.IsNullOrEmpty(name)) name = GetString(store, PKEY_Device_DeviceDesc);
        return string.Format("state={0} name=\"{1}\" id={2}", StateText(state), name, id);
    }

    static string StateText(int state) {
        switch (state) {
            case 1: return "ACTIVE";
            case 2: return "DISABLED";
            case 4: return "NOTPRESENT";
            case 8: return "UNPLUGGED";
            default: return "?" + state;
        }
    }

    public static string Default(int flow, int role) {
        var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev;
        int hr = enumerator.GetDefaultAudioEndpoint(flow, role, out dev);
        if (hr != 0) return "none (hr=0x" + hr.ToString("X8") + ")";
        return Describe(dev);
    }

    public static string[] All(int flow) {
        var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDeviceCollection col;
        enumerator.EnumAudioEndpoints(flow, 0xF, out col);
        int n;
        col.GetCount(out n);
        var list = new string[n];
        for (int i = 0; i < n; i++) {
            IMMDevice d;
            col.Item(i, out d);
            list[i] = Describe(d);
        }
        return list;
    }
}
"@ -ErrorAction Stop

Write-Output '=== default render (console role) ==='
[AudioInfo]::Default(0, 0)
Write-Output '=== default render (multimedia role) ==='
[AudioInfo]::Default(0, 1)
Write-Output '=== default render (communications role) ==='
[AudioInfo]::Default(0, 2)
Write-Output '=== default capture (console role) ==='
[AudioInfo]::Default(1, 0)
Write-Output '=== all render endpoints ==='
[AudioInfo]::All(0) | ForEach-Object { $_ }


