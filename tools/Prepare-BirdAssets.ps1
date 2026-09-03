param(
    [string]$AssetDirectory = "D:\CodexBirdPet\assets"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.IO;

public static class BirdAssetPrep
{
    private static Rectangle LargestVisibleComponentBounds(Bitmap bmp)
    {
        int w=bmp.Width,h=bmp.Height;
        bool[] seen=new bool[w*h];
        int bestArea=0;
        Rectangle best=new Rectangle(0,0,w,h);
        for(int sy=0;sy<h;sy++) for(int sx=0;sx<w;sx++){
            int start=sy*w+sx;
            if(seen[start])continue;
            if(bmp.GetPixel(sx,sy).A<=12){seen[start]=true;continue;}
            int area=0,minX=sx,maxX=sx,minY=sy,maxY=sy;
            var q=new Queue<int>();q.Enqueue(start);seen[start]=true;
            while(q.Count>0){
                int i=q.Dequeue(),x=i%w,y=i/w;area++;
                minX=Math.Min(minX,x);maxX=Math.Max(maxX,x);minY=Math.Min(minY,y);maxY=Math.Max(maxY,y);
                int[] next={i-1,i+1,i-w,i+w};
                foreach(int ni in next){
                    if(ni<0||ni>=w*h||seen[ni])continue;
                    int nx=ni%w,ny=ni/w;
                    if(Math.Abs(nx-x)+Math.Abs(ny-y)!=1)continue;
                    if(bmp.GetPixel(nx,ny).A>12){seen[ni]=true;q.Enqueue(ni);}
                }
            }
            if(area>bestArea){bestArea=area;best=new Rectangle(minX,minY,maxX-minX+1,maxY-minY+1);}
        }
        return best;
    }

    private static Rectangle GreenBodyBounds(Bitmap bmp)
    {
        int minX=bmp.Width,minY=bmp.Height,maxX=-1,maxY=-1;
        for(int y=0;y<bmp.Height;y++) for(int x=0;x<bmp.Width;x++){
            Color c=bmp.GetPixel(x,y);
            bool greenBody=c.A>12&&c.G>100&&c.G>c.R+12&&c.G>c.B+30;
            if(greenBody){minX=Math.Min(minX,x);minY=Math.Min(minY,y);maxX=Math.Max(maxX,x);maxY=Math.Max(maxY,y);}
        }
        if(maxX<minX||maxY<minY)return LargestVisibleComponentBounds(bmp);
        return new Rectangle(minX,minY,maxX-minX+1,maxY-minY+1);
    }

    private static bool IsBackground(Color c)
    {
        int max = Math.Max(c.R, Math.Max(c.G, c.B));
        int min = Math.Min(c.R, Math.Min(c.G, c.B));
        return min >= 222 && (max - min) <= 18;
    }

    public static void RemoveConnectedCheckerboard(string input, string output)
    {
        using (var src = new Bitmap(input))
        using (var bmp = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb))
        {
            using (var g = Graphics.FromImage(bmp)) g.DrawImageUnscaled(src, 0, 0);
            int w = bmp.Width, h = bmp.Height;
            var seen = new bool[w * h];
            var queue = new Queue<int>();

            Action<int,int> add = (x,y) => {
                int i = y * w + x;
                if (!seen[i] && IsBackground(bmp.GetPixel(x,y))) {
                    seen[i] = true;
                    queue.Enqueue(i);
                }
            };

            for (int x = 0; x < w; x++) { add(x,0); add(x,h-1); }
            for (int y = 1; y < h-1; y++) { add(0,y); add(w-1,y); }

            while (queue.Count > 0) {
                int i = queue.Dequeue();
                int x = i % w, y = i / w;
                if (x > 0) add(x-1,y);
                if (x+1 < w) add(x+1,y);
                if (y > 0) add(x,y-1);
                if (y+1 < h) add(x,y+1);
            }

            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if (seen[y*w+x]) {
                        var c = bmp.GetPixel(x,y);
                        bmp.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));
                    }

            bmp.Save(output, ImageFormat.Png);
        }
    }

    public static void CopyAsArgb(string input, string output)
    {
        using (var src = new Bitmap(input))
        using (var bmp = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb)) {
            using (var g = Graphics.FromImage(bmp)) g.DrawImageUnscaled(src, 0, 0);
            bmp.Save(output, ImageFormat.Png);
        }
    }

    public static void SplitSix(string sheet, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        using (var src = new Bitmap(sheet)) {
            for (int frame = 0; frame < 6; frame++) {
                int left = (int)Math.Round(frame * src.Width / 6.0);
                int right = (int)Math.Round((frame + 1) * src.Width / 6.0);
                int width = right - left;
                using (var part = new Bitmap(width, src.Height, PixelFormat.Format32bppArgb)) {
                    using (var g = Graphics.FromImage(part)) {
                        g.Clear(Color.Transparent);
                        g.DrawImage(src, new Rectangle(0,0,width,src.Height), new Rectangle(left,0,width,src.Height), GraphicsUnit.Pixel);
                    }
                    part.Save(Path.Combine(outputDirectory, String.Format("frame-{0:00}.png", frame + 1)), ImageFormat.Png);
                }
            }
        }
    }

    public static void NormalizeSix(string inputDirectory, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var frames = new List<Bitmap>();
        try {
            for (int i = 1; i <= 6; i++)
                frames.Add(new Bitmap(Path.Combine(inputDirectory, String.Format("frame-{0:00}.png", i))));

            int minX = Int32.MaxValue, minY = Int32.MaxValue, maxX = -1, maxY = -1;
            foreach (var frame in frames) {
                for (int y = 0; y < frame.Height; y++)
                    for (int x = 0; x < frame.Width; x++)
                        if (frame.GetPixel(x,y).A > 8) {
                            minX = Math.Min(minX,x); minY = Math.Min(minY,y);
                            maxX = Math.Max(maxX,x); maxY = Math.Max(maxY,y);
                        }
            }
            if (maxX < minX || maxY < minY) throw new InvalidOperationException("No visible pixels found.");
            var bodyBounds=new List<Rectangle>();
            int maxBodyW=1,maxBodyH=1;
            foreach(var frame in frames){
                Rectangle body=GreenBodyBounds(frame);bodyBounds.Add(body);
                maxBodyW=Math.Max(maxBodyW,body.Width);maxBodyH=Math.Max(maxBodyH,body.Height);
            }
            for (int i = 0; i < frames.Count; i++) {
                Rectangle subject=bodyBounds[i];
                // Normalize each generated pose by the bird body. This removes
                // source-sheet size drift between idle/thinking/complete states.
                double scale=Math.Min(330.0/subject.Width,320.0/subject.Height);
                double subjectCenter=subject.Left+subject.Width/2.0;
                int drawX=(int)Math.Round(256.0-subjectCenter*scale);
                // Anchor the bird itself. Props can approach the edge, but they
                // must never shrink or move the bird.
                double subjectBottom=subject.Bottom;
                int drawY=(int)Math.Round(438.0-subjectBottom*scale);
                int drawW=(int)Math.Round(frames[i].Width*scale);
                int drawH=(int)Math.Round(frames[i].Height*scale);
                using (var canvas = new Bitmap(512,512,PixelFormat.Format32bppArgb))
                using (var g = Graphics.FromImage(canvas)) {
                    g.Clear(Color.Transparent);
                    g.CompositingMode = CompositingMode.SourceOver;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    g.DrawImage(frames[i], new Rectangle(drawX,drawY,drawW,drawH), new Rectangle(0,0,frames[i].Width,frames[i].Height), GraphicsUnit.Pixel);
                    RemoveNeutralSideFragments(canvas);
                    RemoveSmallIslands(canvas, 64);
                    canvas.Save(Path.Combine(outputDirectory,String.Format("frame-{0:00}.png",i+1)),ImageFormat.Png);
                }
            }
        } finally {
            foreach (var frame in frames) frame.Dispose();
        }
    }

    private static void RemoveSmallIslands(Bitmap bmp, int minimumArea)
    {
        int w=bmp.Width,h=bmp.Height;
        bool[] seen=new bool[w*h];
        for(int sy=0;sy<h;sy++) for(int sx=0;sx<w;sx++) {
            int start=sy*w+sx;
            if(seen[start]) continue;
            Color startColor=bmp.GetPixel(sx,sy);
            if(startColor.A<=12){seen[start]=true;continue;}
            var component=new List<int>();
            var q=new Queue<int>(); q.Enqueue(start); seen[start]=true;
            while(q.Count>0){
                int i=q.Dequeue(),x=i%w,y=i/w; component.Add(i);
                int[] next={i-1,i+1,i-w,i+w};
                foreach(int ni in next){
                    if(ni<0||ni>=w*h||seen[ni]) continue;
                    int nx=ni%w,ny=ni/w;
                    if(Math.Abs(nx-x)+Math.Abs(ny-y)!=1) continue;
                    Color c=bmp.GetPixel(nx,ny);
                    if(c.A>12){seen[ni]=true;q.Enqueue(ni);}
                }
            }
            if(component.Count<minimumArea)
                foreach(int i in component){int x=i%w,y=i/w;Color c=bmp.GetPixel(x,y);bmp.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));}
        }
        for(int y=0;y<h;y++) for(int x=0;x<w;x++){
            Color c=bmp.GetPixel(x,y);
            if(c.A>0&&c.A<=12) bmp.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));
        }
    }

    private static void RemoveNeutralSideFragments(Bitmap bmp)
    {
        for (int y = 0; y < bmp.Height; y++) {
            int left = bmp.Width, right = -1;
            for (int x = 0; x < bmp.Width; x++) {
                Color c = bmp.GetPixel(x,y);
                int max = Math.Max(c.R, Math.Max(c.G,c.B));
                int min = Math.Min(c.R, Math.Min(c.G,c.B));
                bool structural = c.A > 8 && ((max-min) > 18 || min < 205);
                if (structural) { left = Math.Min(left,x); right = Math.Max(right,x); }
            }
            if (right < left) continue;
            for (int x = 0; x < bmp.Width; x++) {
                Color c = bmp.GetPixel(x,y);
                int max = Math.Max(c.R, Math.Max(c.G,c.B));
                int min = Math.Min(c.R, Math.Min(c.G,c.B));
                bool neutralBright = c.A > 0 && min > 205 && (max-min) <= 18;
                if (neutralBright && (x < left-3 || x > right+3))
                    bmp.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));
            }
        }
    }

    public static int[] ComponentAreas(string path)
    {
        using (var bmp = new Bitmap(path)) {
            int w=bmp.Width,h=bmp.Height;
            bool[] seen=new bool[w*h];
            var areas=new List<int>();
            for(int sy=0;sy<h;sy++) for(int sx=0;sx<w;sx++) {
                int start=sy*w+sx;
                if(seen[start] || bmp.GetPixel(sx,sy).A<=8) continue;
                int area=0;
                var q=new Queue<int>(); q.Enqueue(start); seen[start]=true;
                while(q.Count>0){
                    int i=q.Dequeue(),x=i%w,y=i/w; area++;
                    int[] next={i-1,i+1,i-w,i+w};
                    for(int n=0;n<4;n++){
                        int ni=next[n];
                        if(ni<0||ni>=w*h||seen[ni]) continue;
                        int nx=ni%w,ny=ni/w;
                        if(Math.Abs(nx-x)+Math.Abs(ny-y)!=1) continue;
                        if(bmp.GetPixel(nx,ny).A>8){seen[ni]=true;q.Enqueue(ni);}
                    }
                }
                areas.Add(area);
            }
            areas.Sort(); areas.Reverse(); return areas.ToArray();
        }
    }

    public static void KeepLargestComponent(string path)
    {
        using(var bmp=new Bitmap(path)){
            int w=bmp.Width,h=bmp.Height;
            bool[] seen=new bool[w*h];
            var components=new List<List<int>>();
            for(int sy=0;sy<h;sy++) for(int sx=0;sx<w;sx++){
                int start=sy*w+sx;
                if(seen[start]) continue;
                Color first=bmp.GetPixel(sx,sy);
                if(first.A<=8){seen[start]=true;continue;}
                var component=new List<int>();
                var q=new Queue<int>();q.Enqueue(start);seen[start]=true;
                while(q.Count>0){
                    int i=q.Dequeue(),x=i%w,y=i/w;component.Add(i);
                    int[] next={i-1,i+1,i-w,i+w};
                    foreach(int ni in next){
                        if(ni<0||ni>=w*h||seen[ni])continue;
                        int nx=ni%w,ny=ni/w;
                        if(Math.Abs(nx-x)+Math.Abs(ny-y)!=1)continue;
                        if(bmp.GetPixel(nx,ny).A>8){seen[ni]=true;q.Enqueue(ni);}
                    }
                }
                components.Add(component);
            }
            components.Sort((a,b)=>b.Count.CompareTo(a.Count));
            for(int c=1;c<components.Count;c++) foreach(int i in components[c]){
                int x=i%w,y=i/w;Color color=bmp.GetPixel(x,y);
                bmp.SetPixel(x,y,Color.FromArgb(0,color.R,color.G,color.B));
            }
            bmp.Save(path+".new",ImageFormat.Png);
        }
        File.Delete(path);
        File.Move(path+".new",path);
    }

    public static void ClearOutsideHorizontalSafeArea(string path, int left, int right)
    {
        using(var bmp=new Bitmap(path)){
            for(int y=0;y<bmp.Height;y++) for(int x=0;x<bmp.Width;x++){
                if(x>=left&&x<=right) continue;
                Color c=bmp.GetPixel(x,y);
                if(c.A>0) bmp.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));
            }
            bmp.Save(path+".new",ImageFormat.Png);
        }
        File.Delete(path);
        File.Move(path+".new",path);
    }

    public static void KeepCentralRunPerRow(string path, int untilY)
    {
        using(var bmp=new Bitmap(path)){
            int center=bmp.Width/2;
            for(int y=0;y<Math.Min(untilY,bmp.Height);y++){
                var runs=new List<int[]>();
                int start=-1;
                for(int x=0;x<=bmp.Width;x++){
                    bool visible=x<bmp.Width&&bmp.GetPixel(x,y).A>8;
                    if(visible&&start<0)start=x;
                    if(!visible&&start>=0){runs.Add(new int[]{start,x-1});start=-1;}
                }
                if(runs.Count<=1)continue;
                int keep=0,best=Int32.MaxValue;
                for(int i=0;i<runs.Count;i++){
                    int distance=center<runs[i][0]?runs[i][0]-center:center>runs[i][1]?center-runs[i][1]:0;
                    if(distance<best){best=distance;keep=i;}
                }
                for(int i=0;i<runs.Count;i++)if(i!=keep)
                    for(int x=runs[i][0];x<=runs[i][1];x++){
                        Color c=bmp.GetPixel(x,y);bmp.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));
                    }
            }
            bmp.Save(path+".new",ImageFormat.Png);
        }
        File.Delete(path);
        File.Move(path+".new",path);
    }
}
'@

$drawingAssembly = [System.Drawing.Bitmap].Assembly.Location
$primitivesAssembly = [System.Drawing.Color].Assembly.Location
Add-Type -TypeDefinition $source -ReferencedAssemblies @($drawingAssembly, $primitivesAssembly)

$states = @(
    @{ Name = "idle"; File = "idle-sheet-v2.png"; Transparent = $false },
    @{ Name = "typing"; File = "typing-sheet-v2.png"; Transparent = $false },
    @{ Name = "thinking"; File = "thinking-sheet-v3.png"; Transparent = $false },
    @{ Name = "complete"; File = "complete-sheet-v3.png"; Transparent = $false },
    @{ Name = "waiting"; File = "waiting-sheet-v2.png"; Transparent = $false }
)

$prepared = Join-Path $AssetDirectory "prepared-v12"
New-Item -ItemType Directory -Force -Path $prepared | Out-Null

foreach ($state in $states) {
    $input = Join-Path $AssetDirectory $state.File
    $sheetOutput = Join-Path $prepared ($state.Name + "-sheet.png")
    if ($state.Transparent) {
        [BirdAssetPrep]::CopyAsArgb($input, $sheetOutput)
    } else {
        [BirdAssetPrep]::RemoveConnectedCheckerboard($input, $sheetOutput)
    }
    $splitDirectory = Join-Path $prepared ("split-" + $state.Name)
    [BirdAssetPrep]::SplitSix($sheetOutput, $splitDirectory)
    $finalDirectory = Join-Path $prepared $state.Name
    [BirdAssetPrep]::NormalizeSix($splitDirectory, $finalDirectory)
}

Get-ChildItem -LiteralPath $prepared -Recurse -Filter *.png | Select-Object FullName, Length
