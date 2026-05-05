import { Schema } from "./schema";

export type Store<T> = {
	readonly source: DataStore;
	readonly schema: Schema<T>;

	readonly lock: { [key: string]: ((data: T) => T)[] };

	readonly session: {
		readonly time: number;

		readonly state: { [key: string]: "starting" | "active" };
		readonly waiting: { [key: string]: thread[] };
		readonly loop: { [key: string]: thread };
		readonly cache: { [key: string]: T };
		readonly queue: { [key: string]: ((data: T) => T)[] };
		readonly observers: ((key: string, data: T) => void)[];
	};
};

type StoreOptions<T> = {
	name: string;
	schema: Schema<T>;
	sessiontime?: number;
};

export function create<T>(opts: StoreOptions<T>): Store<T>;

export function startsession<T>(store: Store<T>, key: string): void;

export function waitforsession<T>(store: Store<T>, key: string): void;

export function issessionactive<T>(store: Store<T>, key: string): boolean;

export function stopsessionasync<T>(store: Store<T>, key: string): thread;

export function view<T>(store: Store<T>, key: string): T;

export function update<T>(
	store: Store<T>,
	key: string,
	fn: (data: T) => T,
): void;

export function observe<T>(
	store: Store<T>,
	fn: (key: string, data: T) => void,
): void;

export function viewasync<T>(store: Store<T>, key: string): T;

export function updateasync<T>(
	store: Store<T>,
	key: string,
	fn: (data: T) => T,
): T;

export function txasync<T>(
	fn: (
		tx: <T>(store: Store<T>, key: string, fn: (data: T) => T) => void,
	) => void,
): void;
