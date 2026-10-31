/** Files handed from the library to a project in this visit; `process` starts the pipeline. */
export const pendingFiles = new Map<string, { file: File; process: boolean }>();
