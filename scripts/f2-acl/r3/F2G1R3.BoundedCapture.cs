// Inert Windows CI child-stream capture: bounded retention and continuous drain.
// This is test infrastructure, not a trusted or protected C: component.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
namespace F2G1R3Synthetic {
  public sealed class BoundedResult {
    public string Text;
    public long Dropped;
    public bool Overflow { get { return Dropped>0; } }
  }
  public static class BoundedCapture {
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="CreateHardLinkW")]
    [return:MarshalAs(UnmanagedType.Bool)]
    public static extern bool CreateHardLink(string linkName,string targetName,IntPtr reserved);
    public static Task<BoundedResult> Drain(StreamReader stream,int limit) {
      if(stream==null||limit<1||limit>4096)throw new ArgumentOutOfRangeException("limit");
      return Task.Factory.StartNew<BoundedResult>(() => {
        char[] chunk=new char[2048];
        StringBuilder retained=new StringBuilder(limit);
        long dropped=0; int n;
        while((n=stream.Read(chunk,0,chunk.Length))>0) {
          int taken=Math.Min(n,limit-retained.Length);
          if(taken>0)retained.Append(chunk,0,taken);
          dropped+=n-taken;
        }
        return new BoundedResult{Text=retained.ToString(),Dropped=dropped};
      },CancellationToken.None,TaskCreationOptions.LongRunning,TaskScheduler.Default);
    }
  }
}
