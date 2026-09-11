/*
 * dcent-steam-workshop — subscribe/download a Steam Workshop item through the
 * locally running, already-signed-in Steam client.
 *
 * Uses the Steam client's own libsteam_api.so via the flat C API, so no
 * Steamworks SDK headers, no API key and no web sign-in are required:
 *
 *     SteamAPI_InitFlat()  -> attaches to the running client's session
 *     ISteamUGC::SubscribeItem() + DownloadItem(highPriority)
 *
 * The client then downloads the item into its configured Steam library, where
 * the plasma plugin's status polling picks it up.
 *
 * Build (see build.sh):  gcc -O2 -o dcent-steam-workshop dcent-steam-workshop.c \
 *                           -L"$STEAM_LIBDIR" -lsteam_api -Wl,-rpath,"$STEAM_LIBDIR"
 *
 * usage: dcent-steam-workshop <workshopId> [--unsub|--state]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>

extern int  SteamAPI_InitFlat(char *pOutErrMsg);
extern void SteamAPI_Shutdown(void);
extern void *SteamAPI_SteamUGC_v021(void);
extern unsigned long long SteamAPI_ISteamUGC_SubscribeItem(void *ugc, unsigned long long id);
extern unsigned long long SteamAPI_ISteamUGC_UnsubscribeItem(void *ugc, unsigned long long id);
extern int  SteamAPI_ISteamUGC_DownloadItem(void *ugc, unsigned long long id, int highPriority);
extern unsigned int SteamAPI_ISteamUGC_GetItemState(void *ugc, unsigned long long id);

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <workshopId> [--unsub|--state]\n", argv[0]);
        return 2;
    }

    /* SteamAPI_InitFlat reads steam_appid.txt from the current directory. */
    char exe[4096];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n > 0) {
        exe[n] = '\0';
        chdir(dirname(exe));
    }

    char err[1024];
    err[0] = '\0';
    int rc = SteamAPI_InitFlat(err);
    if (rc != 0) {
        fprintf(stderr, "SteamAPI_InitFlat failed: %d %s\n", rc, err);
        return 3;
    }

    void *ugc = SteamAPI_SteamUGC_v021();
    if (!ugc) {
        fprintf(stderr, "ISteamUGC unavailable\n");
        SteamAPI_Shutdown();
        return 4;
    }

    unsigned long long id = strtoull(argv[1], NULL, 10);
    if (id == 0) {
        fprintf(stderr, "invalid workshop id: %s\n", argv[1]);
        SteamAPI_Shutdown();
        return 5;
    }

    printf("id=%llu state=%u\n", id, SteamAPI_ISteamUGC_GetItemState(ugc, id));

    int status = 0;
    if (argc > 2 && strcmp(argv[2], "--state") == 0) {
        /* query only */
    } else if (argc > 2 && strcmp(argv[2], "--unsub") == 0) {
        SteamAPI_ISteamUGC_UnsubscribeItem(ugc, id);
        printf("unsubscribed\n");
    } else {
        SteamAPI_ISteamUGC_SubscribeItem(ugc, id);
        int ok = SteamAPI_ISteamUGC_DownloadItem(ugc, id, 1);
        printf("subscribed download(highPriority)=%d\n", ok);
        if (!ok)
            status = 6;
    }

    SteamAPI_Shutdown();
    return status;
}
