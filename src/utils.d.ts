import { Entity } from "@rbxts/jecs";
import { World } from "@rbxts/jecs";
import { Components, Shared } from "./common";

export declare class cursor {
    public offset: number;
    public buffer: buffer;

    constructor();
    static from(buffer: buffer): cursor;
    static tryalloc(cursor: cursor, bytes: number): void;
    static write_buffer(cursor: cursor, buffer: buffer): void;
    static writeu8(cursor: cursor, value: number): void;
    static writeu16(cursor: cursor, value: number): void;
    static writeu24(cursor: cursor, value: number): void;
    static writeu32(cursor: cursor, value: number): void;
    static writei8(cursor: cursor, value: number): void;
    static writei16(cursor: cursor, value: number): void;
    static writei32(cursor: cursor, value: number): void;
    static read_buffer(cursor: cursor, len: number): buffer;
    static readu8(cursor: cursor): number;
    static readu16(cursor: cursor): number;
    static readu24(cursor: cursor): number;
    static readu32(cursor: cursor): number;
    static readi8(cursor: cursor): number;
    static readi16(cursor: cursor): number;
    static readi32(cursor: cursor): number;
    static write_vlq(cursor: cursor, value: number): void;
    static read_vlq(cursor: cursor): number;
    static close(cursor: cursor): buffer;
}

export declare class bitmask {
    public buffer: buffer;
    public capacity: number;
    public entries: number;

    static create(capacity?: number): bitmask;
    static from_set(
        indexes: Map<unknown, number>,
        filter: Map<unknown, boolean>,
        capacity?: number
    ): bitmask;

    expand(capacity: number): void;
    read(index: number): number;
    write(index: number, value: number): void;
    set(index: number): void;
    get(index: number): boolean;
    clear(index: number): void;
    band(other: bitmask): bitmask;
    bor(other: bitmask): bitmask;
    bxor(other: bitmask): bitmask;
    bnot(): bitmask;
    clone(): bitmask;
    remap(
        from: Map<unknown, number>,
        to: Map<unknown, number>,
        new_capacity?: number
    ): bitmask;
    lshift(n: number): bitmask;
    rshift(n: number): bitmask;
    tostring(): string;
}

declare function create_shared_lookup(
    world: World,
    components: Components
): Shared;
declare function vlq_span(length: number): number;
declare function number_span(n: number): number;
declare function read_number(
    buf: buffer,
    offset: number,
    span: number
): LuaTuple<[number, number]>;
declare function remove_all_relations(
    world: World,
    entity: Entity,
    relation: Entity
): void;
declare function logerror(...args: any[]): void;
declare function logwarn(...args: any[]): void;
declare function logcomponent(world: World, component: Entity): void;
