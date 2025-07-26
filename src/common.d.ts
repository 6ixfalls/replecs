import { Id } from "@rbxts/jecs";
import { Tag } from "@rbxts/jecs";
import { World } from "@rbxts/jecs";
import { Entity } from "@rbxts/jecs";

export type PlayerFilter = Map<Player, boolean>;

export interface Serdes {
    serialize: (value: any) => buffer;
    deserialize: (buffer: buffer) => any;
}

export interface Components {
    shared: Tag;
    networked: Entity<PlayerFilter | undefined>;
    reliable: Entity<PlayerFilter | undefined>;
    unreliable: Entity<PlayerFilter | undefined>;
    pair: Tag;

    serdes: Entity<Serdes>;
    bytespan: Entity<number>;
    custom_id: Entity<(value: any) => Entity>;
    __alive_tracking__: Tag;
}

export interface Shared {
    lookup: Map<string, Entity>;

    components: Map<number, Entity>;
    ids: Map<Entity, number>;

    bytespan: Map<Entity, number>;
    serdes: Map<Entity, Serdes>;
}

export interface WorldHooks {
    added<T>(
        this: World,
        id: Id<T>,
        callback: (e: Entity, id: Id<T>, value: T) => void
    ): void;
    changed<T>(
        this: World,
        id: Id<T>,
        callback: (e: Entity, id: Id<T>, value: T) => void
    ): void;
    removed(this: World, id: Id, callback: (e: Entity, id: Id) => void): void;
}
