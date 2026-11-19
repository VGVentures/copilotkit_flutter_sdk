// Pure helpers for server.ts, kept apart so they can be tested without
// starting a server.

/** Learning container used when CPK_INTELLIGENCE_LEARNING_CONTAINER_ID is unset. */
export const defaultLearningContainerId = "flutter-example";

/** Identity used when the app sends no demo identity header. */
// Keeps the id Intelligence mode already used on main, so a thread the app saved
// before the Learning container existed still belongs to the same user.
export const defaultUser = { id: "example-user", name: "Flutter example" };

// Intelligence accepts 1-64 lowercase letters or digits, joined by single hyphens.
const containerIdPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/**
 * Returns the Learning container id to assign threads to, from the value of
 * CPK_INTELLIGENCE_LEARNING_CONTAINER_ID. Throws on an invalid id, so a typo
 * stops the runtime at startup instead of failing every run. A thread's
 * container is permanent, so a wrong id can't be fixed afterwards.
 */
export function resolveLearningContainerId(value: string | undefined): string {
  const id = value?.trim() || defaultLearningContainerId;
  if (id.length > 64 || !containerIdPattern.test(id)) {
    throw new Error(
      `CPK_INTELLIGENCE_LEARNING_CONTAINER_ID="${id}" is invalid. Use 1-64 ` +
        "lowercase letters, numbers or single hyphens, e.g. expense-review.",
    );
  }
  return id;
}
