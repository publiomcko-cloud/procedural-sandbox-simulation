// F2 G1 R3 experimental TEMP-only native handle contract.
// NOT a live C: inspector. Path-based protected inspection is deliberately absent.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace F2G1R3 {
  public static class TempHandleProbe {
    const uint READ_CONTROL=0x20000, SYNCHRONIZE=0x100000, READ_DATA=1, READ_ATTRIBUTES=0x80;
    const uint SHARE_READ=1, OPEN_EXISTING=3, NT_FILE_OPEN=1;
    const uint DIRECTORY=0x10, REPARSE=0x400, OPEN_REPARSE=0x200000, BACKUP_SEMANTICS=0x02000000;
    const uint NT_DIRECTORY=1, NT_NON_DIRECTORY=0x40, NT_SYNCHRONOUS=0x20;
    const int STATUS_NO_MORE_FILES=unchecked((int)0x80000006);
    [StructLayout(LayoutKind.Sequential)] struct UnicodeString {public ushort Length,MaximumLength;public IntPtr Buffer;}
    [StructLayout(LayoutKind.Sequential)] struct ObjectAttributes {public int Length;public IntPtr RootDirectory,ObjectName;public uint Attributes;public IntPtr SecurityDescriptor,SecurityQualityOfService;}
    [StructLayout(LayoutKind.Sequential)] struct IoStatusBlock {public IntPtr Status,Information;}
    [StructLayout(LayoutKind.Sequential)] struct FileTime {public uint Low,High;}
    [StructLayout(LayoutKind.Sequential)] struct FileInformation {
      public uint Attributes;public FileTime Created,Accessed,Written;
      public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
    }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,EntryPoint="CreateFileW",SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
    [DllImport("ntdll.dll")]
    static extern int NtCreateFile(out SafeFileHandle handle,uint access,ref ObjectAttributes oa,out IoStatusBlock status,IntPtr allocation,uint attributes,uint share,uint disposition,uint options,IntPtr ea,uint eaLength);
    [DllImport("ntdll.dll")]
    static extern int NtQueryDirectoryFile(SafeFileHandle handle,IntPtr evt,IntPtr apc,IntPtr context,out IoStatusBlock status,IntPtr buffer,uint bufferSize,int infoClass,bool single,IntPtr filter,bool restart);
    [DllImport("kernel32.dll",SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool GetFileInformationByHandle(SafeFileHandle handle,out FileInformation info);
    [DllImport("kernel32.dll",SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool ReadFile(SafeFileHandle handle,byte[] buffer,uint requested,out uint got,IntPtr overlapped);
    [DllImport("advapi32.dll")]
    static extern uint GetSecurityInfo(IntPtr handle,uint type,uint requested,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr descriptor,uint revision,uint requested,out IntPtr sddl,out uint length);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);

    static void Require(bool ok,string error) {if(!ok)throw new InvalidOperationException(error);}
    static string Digest(byte[] bytes) {using(SHA256 sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
    static FileInformation GetInfo(SafeFileHandle h,string stage) {
      FileInformation info=default(FileInformation);
      Require(h!=null&&!h.IsInvalid&&!h.IsClosed&&GetFileInformationByHandle(h,out info),"HANDLE_INFO_UNAVAILABLE_"+stage);
      return info;
    }
    static string Id(FileInformation f){return f.Volume.ToString("x8")+":"+f.IndexHigh.ToString("x8")+f.IndexLow.ToString("x8");}
    static void VerifyType(FileInformation f,bool directory){
      Require((f.Attributes&REPARSE)==0,"REPARSE_POINT_DENIED");
      Require(((f.Attributes&DIRECTORY)!=0)==directory,"OBJECT_KIND_CHANGED");
    }
    static string AclDigest(SafeFileHandle h) {
      IntPtr owner,group,dacl,sacl,descriptor,sddl=IntPtr.Zero;uint length;
      uint rc=GetSecurityInfo(h.DangerousGetHandle(),1,5,out owner,out group,out dacl,out sacl,out descriptor);
      Require(rc==0&&descriptor!=IntPtr.Zero,"HANDLE_OWNER_DACL_UNREADABLE");
      try {
        Require(ConvertSecurityDescriptorToStringSecurityDescriptor(descriptor,1,5,out sddl,out length)&&sddl!=IntPtr.Zero,"HANDLE_SDDL_CONVERSION_FAILED");
        return Digest(Encoding.Unicode.GetBytes(Marshal.PtrToStringUni(sddl)));
      } finally {if(sddl!=IntPtr.Zero)LocalFree(sddl);LocalFree(descriptor);}
    }
    static SafeFileHandle OpenRelativeFile(SafeFileHandle parent) {
      const string name="payload.bin";IntPtr buffer=IntPtr.Zero,unicode=IntPtr.Zero;
      try {
        buffer=Marshal.StringToHGlobalUni(name);
        UnicodeString u=new UnicodeString();u.Length=(ushort)(name.Length*2);u.MaximumLength=(ushort)((name.Length+1)*2);u.Buffer=buffer;
        unicode=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
        Marshal.StructureToPtr(u,unicode,false);
        ObjectAttributes oa=new ObjectAttributes();
        oa.Length=Marshal.SizeOf(typeof(ObjectAttributes));oa.RootDirectory=parent.DangerousGetHandle();
        oa.ObjectName=unicode;oa.Attributes=0x40; // OBJ_CASE_INSENSITIVE
        SafeFileHandle result;IoStatusBlock status;
        int rc=NtCreateFile(out result,READ_CONTROL|SYNCHRONIZE|READ_DATA|READ_ATTRIBUTES,ref oa,out status,IntPtr.Zero,0,SHARE_READ,NT_FILE_OPEN,OPEN_REPARSE|NT_SYNCHRONOUS|NT_NON_DIRECTORY,IntPtr.Zero,0);
        if(rc!=0||result==null||result.IsInvalid){if(result!=null)result.Dispose();throw new InvalidOperationException("RELATIVE_NOFOLLOW_OPEN_FAILED");}
        return result;
      } finally {if(unicode!=IntPtr.Zero)Marshal.FreeHGlobal(unicode);if(buffer!=IntPtr.Zero)Marshal.FreeHGlobal(buffer);}
    }
    static SafeFileHandle OpenRelativeDirectory(SafeFileHandle parent,string name) {
      // Never accept separators or caller-supplied path components.
      Guid fixtureId;
      bool fixedParent=name=="Users"||name=="Public";
      bool fixtureName=name.StartsWith("F2G1-R3Handle-",StringComparison.Ordinal)
        &&Guid.TryParseExact(name.Substring(14),"D",out fixtureId);
      Require(fixedParent||fixtureName,"RELATIVE_DIRECTORY_COMPONENT_DENIED");
      IntPtr buffer=IntPtr.Zero,unicode=IntPtr.Zero;
      try {
        buffer=Marshal.StringToHGlobalUni(name);
        UnicodeString u=new UnicodeString();u.Length=checked((ushort)(name.Length*2));
        u.MaximumLength=checked((ushort)((name.Length+1)*2));u.Buffer=buffer;
        unicode=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
        Marshal.StructureToPtr(u,unicode,false);
        ObjectAttributes oa=new ObjectAttributes();oa.Length=Marshal.SizeOf(typeof(ObjectAttributes));
        oa.RootDirectory=parent.DangerousGetHandle();oa.ObjectName=unicode;oa.Attributes=0x40;
        SafeFileHandle result;IoStatusBlock status;
        int rc=NtCreateFile(out result,READ_CONTROL|SYNCHRONIZE|READ_DATA|READ_ATTRIBUTES,
          ref oa,out status,IntPtr.Zero,0,SHARE_READ,NT_FILE_OPEN,
          OPEN_REPARSE|NT_SYNCHRONOUS|NT_DIRECTORY,IntPtr.Zero,0);
        if(rc!=0||result==null||result.IsInvalid) {
          if(result!=null)result.Dispose();
          throw new InvalidOperationException("RELATIVE_DIRECTORY_OPEN_FAILED");
        }
        return result;
      } finally {
        if(unicode!=IntPtr.Zero)Marshal.FreeHGlobal(unicode);
        if(buffer!=IntPtr.Zero)Marshal.FreeHGlobal(buffer);
      }
    }
    static string Entries(SafeFileHandle dir) {
      // NtQueryDirectoryFile FileNamesInformation=12, bound to a held directory handle.
      IntPtr buffer=Marshal.AllocHGlobal(65536);List<string> names=new List<string>();bool restart=true;
      try {
        for(int call=0;call<32;call++){
          IoStatusBlock status;
          int rc=NtQueryDirectoryFile(dir,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,out status,buffer,65536,12,false,IntPtr.Zero,restart);
          restart=false;
          if(rc==STATUS_NO_MORE_FILES)break;
          Require(rc==0,"HANDLE_ENUM_FAILED");
          long size=status.Information.ToInt64();Require(size>0&&size<=65536,"HANDLE_ENUM_SIZE_INVALID");
          int pos=0;
          for(int n=0;n<1024;n++){
            Require(pos+12<=size,"ENTRY_TRUNCATED");
            int next=Marshal.ReadInt32(buffer,pos),byteCount=Marshal.ReadInt32(buffer,pos+8);
            Require(byteCount>=2&&byteCount%2==0&&pos+12+byteCount<=size,"ENTRY_INVALID");
            string name=Marshal.PtrToStringUni(IntPtr.Add(buffer,pos+12),byteCount/2);
            if(name!="."&&name!="..")names.Add(name);
            if(next==0)break;
            Require(next>=12&&pos+next<size,"ENTRY_OFFSET_INVALID");pos+=next;
          }
          if(call==31)throw new InvalidOperationException("ENUM_LIMIT_EXCEEDED");
        }
        names.Sort(StringComparer.Ordinal);
        Require(names.Count==1&&names[0]=="payload.bin","UNEXPECTED_OR_MISSING_CHILD");
        return String.Join("|",names.ToArray());
      } finally {Marshal.FreeHGlobal(buffer);}
    }
    static byte[] ReadBounded(SafeFileHandle h){
      FileInformation meta=GetInfo(h,"PAYLOAD");
      Require(meta.Links==1,"PAYLOAD_MULTIPLE_LINKS");
      Require(meta.SizeHigh==0&&meta.SizeLow>0&&meta.SizeLow<=4096,"PAYLOAD_SIZE_INVALID");
      byte[] data=new byte[(int)meta.SizeLow];int offset=0;
      while(offset<data.Length){
        byte[] chunk=new byte[Math.Min(1024,data.Length-offset)];uint read;
        Require(ReadFile(h,chunk,(uint)chunk.Length,out read,IntPtr.Zero)&&read>0&&read<=(uint)chunk.Length,"PAYLOAD_INCOMPLETE");
        Buffer.BlockCopy(chunk,0,data,offset,(int)read);offset+=(int)read;
      }
      byte[] tail=new byte[1];uint eof;
      Require(ReadFile(h,tail,1,out eof,IntPtr.Zero)&&eof==0,"PAYLOAD_TRAILING_BYTES");
      // Public exact synthetic test vector, never a host-file hash oracle.
      byte[] known=Encoding.UTF8.GetBytes("TEMP-fixture-only R3.1");
      Require(data.Length==known.Length,"PAYLOAD_TEST_BYTES_MISMATCH");
      for(int i=0;i<data.Length;i++)Require(data[i]==known[i],"PAYLOAD_TEST_BYTES_MISMATCH");
      return data;
    }
    public static string ProbeFixture(string root,bool tryReplace,bool injectIdentityDrift) {
      // Fixed source-reviewed synthetic parent. Environment TEMP/TMP is NOT consulted.
      // The input is a lexically exact one-component child; it is NEVER opened as
      // a full path. All actual opens are relative to previously verified handles.
      Require(!String.IsNullOrEmpty(root),"FIXTURE_REQUIRED");
      string leaf=Path.GetFileName(root.TrimEnd('\\'));Guid id;
      Require(leaf.StartsWith("F2G1-R3Handle-",StringComparison.Ordinal)
        &&Guid.TryParseExact(leaf.Substring(14),"D",out id),"FIXTURE_NAME_INVALID");
      string expected=@"C:\Users\Public\"+leaf;
      Require(String.Equals(root,expected,StringComparison.OrdinalIgnoreCase),"OUTSIDE_FIXED_FIXTURE_ANCHOR");
      using(SafeFileHandle volume=CreateFile(@"\\?\C:\",READ_CONTROL|READ_DATA|READ_ATTRIBUTES,
        SHARE_READ,IntPtr.Zero,OPEN_EXISTING,BACKUP_SEMANTICS|OPEN_REPARSE,IntPtr.Zero)) {
        Require(!volume.IsInvalid,"FIXED_VOLUME_OPEN_FAILED");
        FileInformation volumeInfo=GetInfo(volume,"VOLUME");VerifyType(volumeInfo,true);
        using(SafeFileHandle users=OpenRelativeDirectory(volume,"Users")) {
          FileInformation usersInfo=GetInfo(users,"USERS");VerifyType(usersInfo,true);
          Require(usersInfo.Volume==volumeInfo.Volume,"ANCESTOR_VOLUME_CHANGED");
          using(SafeFileHandle publicRoot=OpenRelativeDirectory(users,"Public")) {
            FileInformation publicInfo=GetInfo(publicRoot,"PUBLIC");VerifyType(publicInfo,true);
            Require(publicInfo.Volume==volumeInfo.Volume,"ANCESTOR_VOLUME_CHANGED");
            using(SafeFileHandle dir=OpenRelativeDirectory(publicRoot,leaf)) {
              FileInformation initialDir=GetInfo(dir,"ROOT");VerifyType(initialDir,true);
              Require(initialDir.Volume==volumeInfo.Volume,"FIXTURE_VOLUME_CHANGED");
              string dirId=Id(initialDir),dirAcl=AclDigest(dir),names=Entries(dir);
              using(SafeFileHandle file=OpenRelativeFile(dir)) {
                FileInformation initial=GetInfo(file,"CHILD");VerifyType(initial,false);
                Require(initial.Volume==volumeInfo.Volume,"CHILD_VOLUME_CHANGED");
                Require(initial.Links==1,"PAYLOAD_MULTIPLE_LINKS");
                string fileId=Id(initial),fileAcl=AclDigest(file);
                if(tryReplace) {
                  bool refused=false;
                  // Path use ONLY as a non-authoritative adversarial rename attempt
                  // in the verified disposable child; never to read bytes or ACL.
                  try{File.Move(expected+@"\payload.bin",expected+@"\renamed.bin");}
                  catch(IOException){refused=true;}catch(UnauthorizedAccessException){refused=true;}
                  Require(refused,"REPLACEMENT_SUCCEEDED_WITH_HELD_HANDLE");
                }
                byte[] bytes=ReadBounded(file);
                if(injectIdentityDrift)throw new InvalidOperationException("INJECTED_FILE_IDENTITY_DRIFT");
                FileInformation finalFile=GetInfo(file,"CHILD_RECHECK");
                Require(finalFile.Links==1,"PAYLOAD_MULTIPLE_LINKS");
                Require(Id(finalFile)==fileId&&AclDigest(file)==fileAcl,
                  "FILE_IDENTITY_OR_ACL_CHANGED");
                Require(Entries(dir)==names&&Id(GetInfo(dir,"ROOT_RECHECK"))==dirId
                  &&AclDigest(dir)==dirAcl,"DIR_IDENTITY_ACL_OR_INVENTORY_CHANGED");
                Require(Id(GetInfo(users,"USERS_RECHECK"))==Id(usersInfo)
                  &&Id(GetInfo(publicRoot,"PUBLIC_RECHECK"))==Id(publicInfo)
                  &&Id(GetInfo(volume,"VOLUME_RECHECK"))==Id(volumeInfo),
                  "ANCESTOR_IDENTITY_CHANGED");
                return "TEMP_HANDLE_FIXTURE_PASS|SHA256="+Digest(bytes)+"|Length="+bytes.Length;
              }
            }
          }
        }
      }
    }
  }
}
