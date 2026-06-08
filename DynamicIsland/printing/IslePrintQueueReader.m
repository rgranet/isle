/*
 * Isle (built on Atoll / DynamicIsland)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#import "IslePrintQueueReader.h"

// CUPS is the macOS printing subsystem. Many of these calls are flagged
// "deprecated" by Apple yet remain the only supported way to read the local
// print queue, so we silence the deprecation noise for this translation unit.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#import <cups/cups.h>

@implementation IslePrintJobInfo
@end

@implementation IslePrintQueueReader

// Fills totalSheets / completedSheets for a job by asking the local CUPS
// scheduler for that job's IPP attributes. Best-effort: leaves the values at 0
// when the driver doesn't report page counts.
+ (void)fillProgressForJob:(IslePrintJobInfo *)info {
    ipp_t *request = ippNewRequest(IPP_OP_GET_JOB_ATTRIBUTES);
    if (!request) return;

    char uri[HTTP_MAX_URI];
    httpAssembleURIf(HTTP_URI_CODING_ALL, uri, sizeof(uri),
                     "ipp", NULL, "localhost", ippPort(), "/jobs/%d", (int)info.jobID);
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "job-uri", NULL, uri);
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", NULL, cupsUser());

    static const char * const attrs[] = {
        "job-impressions", "job-impressions-completed",
        "job-media-sheets", "job-media-sheets-completed"
    };
    ippAddStrings(request, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, "requested-attributes",
                  (int)(sizeof(attrs) / sizeof(attrs[0])), NULL, attrs);

    ipp_t *response = cupsDoRequest(CUPS_HTTP_DEFAULT, request, "/");
    if (!response) return;

    ipp_attribute_t *a;
    NSInteger total = 0, done = 0;

    if ((a = ippFindAttribute(response, "job-media-sheets", IPP_TAG_INTEGER)))
        total = ippGetInteger(a, 0);
    if ((a = ippFindAttribute(response, "job-media-sheets-completed", IPP_TAG_INTEGER)))
        done = ippGetInteger(a, 0);

    // Some drivers only report impressions (logical pages) rather than sheets.
    if (total == 0 && (a = ippFindAttribute(response, "job-impressions", IPP_TAG_INTEGER)))
        total = ippGetInteger(a, 0);
    if (done == 0 && (a = ippFindAttribute(response, "job-impressions-completed", IPP_TAG_INTEGER)))
        done = ippGetInteger(a, 0);

    info.totalSheets = total;
    info.completedSheets = done;

    ippDelete(response);
}

+ (NSArray<IslePrintJobInfo *> *)activeJobs {
    NSMutableArray<IslePrintJobInfo *> *result = [NSMutableArray array];

    cups_job_t *jobs = NULL;
    int numJobs = cupsGetJobs(&jobs, NULL /* all destinations */, 0 /* all users */, CUPS_WHICHJOBS_ACTIVE);
    if (numJobs <= 0 || jobs == NULL) {
        if (jobs) cupsFreeJobs(numJobs, jobs);
        return result;
    }

    for (int i = 0; i < numJobs; i++) {
        cups_job_t *job = &jobs[i];

        switch (job->state) {
            case IPP_JSTATE_PENDING:
            case IPP_JSTATE_HELD:
            case IPP_JSTATE_PROCESSING:
            case IPP_JSTATE_STOPPED:
                break;
            default:
                continue; // completed / canceled / aborted — not interesting
        }

        IslePrintJobInfo *info = [IslePrintJobInfo new];
        info.jobID = job->id;
        info.title = job->title ? [NSString stringWithUTF8String:job->title] : @"";
        info.printer = job->dest ? [NSString stringWithUTF8String:job->dest] : @"";
        info.processing = (job->state == IPP_JSTATE_PROCESSING);
        info.totalSheets = 0;
        info.completedSheets = 0;

        [self fillProgressForJob:info];
        [result addObject:info];
    }

    cupsFreeJobs(numJobs, jobs);
    return result;
}

@end

#pragma clang diagnostic pop
