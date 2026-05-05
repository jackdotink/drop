export type Schema<T> = {
	readonly initial: T;
	readonly migrations: ((state: any) => any)[];
};

export function create<T>(initial: T): Schema<T>;

export function migrate<T, U>(
	schema: Schema<T>,
	migration: (data: T) => U,
): Schema<U>;
