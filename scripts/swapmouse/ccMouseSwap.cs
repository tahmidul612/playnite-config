using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

class SwapMouseConfig
{
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    static void Main(string[] args)
    {
        string configPath = "";
        if (args.Length > 0)
        {
            configPath = args[0]; // Allow passing the config path as an argument
        }
        else
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            configPath = Path.Combine(appData, "ControllerCompanion", "MouseModeBindings.cfg");
        }
        if (!File.Exists(configPath))
        {
            Console.WriteLine("Controller Companion config file not found.");
            return;
        }

        bool rightButtonIsPrimary = GetSystemMetrics(23) != 0; // Check if right button is primary

        string[] lines = File.ReadAllLines(configPath);
        for (int i = 0; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("x @ "))
            {
                lines[i] = rightButtonIsPrimary ? "x @ Left mouse button: mouse left" : "x @ Right mouse button: mouse right";
            }
            else if (lines[i].StartsWith("a @ "))
            {
                lines[i] = rightButtonIsPrimary ? "a @ Right mouse button: mouse right" : "a @ Left mouse button: mouse left";
            }
        }

        File.WriteAllLines(configPath, lines);
        Console.WriteLine("Mouse button mappings updated based on current primary button.");
    }
}
