using GymOfflineSystem.Models;
using GymOfflineSystem.Services;

namespace GymOfflineSystem;

public class Program
{
    public static void Main(string[] args)
    {
        var exePath = AppDomain.CurrentDomain.BaseDirectory;
        var currentDirectory = Directory.GetCurrentDirectory();
        var publishedWebRoot = Path.Combine(exePath, "wwwroot");
        var developmentWebRoot = Path.Combine(currentDirectory, "wwwroot");

        // Use the published EXE layout only when the app is actually running
        // from a deployed folder. During dotnet run / IDE debugging, keep the
        // default project-root behavior so Data and wwwroot resolve correctly.
        var usePublishedLayout = Directory.Exists(publishedWebRoot) && !Directory.Exists(developmentWebRoot);

        var options = usePublishedLayout
            ? new WebApplicationOptions
            {
                Args = args,
                ContentRootPath = exePath,
                WebRootPath = publishedWebRoot
            }
            : new WebApplicationOptions
            {
                Args = args
            };

        var builder = WebApplication.CreateBuilder(options);

        // MVC
        builder.Services.AddControllersWithViews();

        // Offline services
        builder.Services.AddSingleton<JsonFileService>();
        builder.Services.AddSingleton<ClientService>();
        builder.Services.AddSingleton<PaymentService>();
        builder.Services.AddSingleton<AttendanceService>();
        builder.Services.AddSingleton<NotificationService>();
        builder.Services.AddSingleton<ReportService>();
        builder.Services.AddHostedService<DataBackupService>();


        var app = builder.Build();

        // ===============================
        // STARTUP SYSTEM CHECKS
        // ===============================
        try
        {
            using var scope = app.Services.CreateScope();
            var json = scope.ServiceProvider.GetRequiredService<JsonFileService>();
            var clientService = scope.ServiceProvider.GetRequiredService<ClientService>();
            var paymentService = scope.ServiceProvider.GetRequiredService<PaymentService>();

            // 1. Load and auto-recover the core startup files.
            var sys = json.EnsureCoreDataFilesReady();

            // 2. Auto year switch + new payment file
            if (sys.CurrentYear != DateTime.Now.Year)
            {
                sys.CurrentYear = DateTime.Now.Year;
                json.Write("system.json", sys);
                sys = json.EnsureCoreDataFilesReady();
            }

            // 3. Keep legacy counters aligned with the actual stored data.
            clientService.SyncSystemCounters();
            paymentService.SyncSystemCounter();

            // 4. Run business rules after the core files are confirmed readable.
            clientService.AutoDeactivateInactiveMembers();
        }
        catch
        {
            // Startup data issues should never terminate the application.
        }

        // ===============================
        // HTTP PIPELINE
        // ===============================

        if (!app.Environment.IsDevelopment())
        {
            app.UseExceptionHandler("/Home/Error");
            app.UseHsts();
        }

        if (!app.Environment.IsDevelopment())
        {
            app.UseHttpsRedirection();
        }

        app.UseStaticFiles();

        app.UseRouting();

        app.UseAuthorization();

        app.MapControllerRoute(
            name: "default",
            pattern: "{controller=Home}/{action=Index}/{id?}");

        app.Run();
    }
}
