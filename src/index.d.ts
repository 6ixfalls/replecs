import { Server } from "./server";
import { Client } from "./client";
import { Tag, Entity, World } from "@rbxts/jecs";
import { PlayerFilter, Serdes as ISerdes } from "./common";

export declare const shared: Tag;
export declare const networked: Entity<PlayerFilter | undefined>;
export declare const reliable: Entity<PlayerFilter | undefined>;
export declare const unreliable: Entity<PlayerFilter | undefined>;
export declare const pair: Tag;

export declare const serdes: Entity<ISerdes>;
export declare const bytespan: Entity<number>;
export declare const custom_id: Entity<(value: any) => Entity>;
export declare const __alive_tracking__: Tag;
export declare const Serdes: typeof serdes;
export declare const Bytespan: typeof bytespan;
export declare const CustomId: typeof custom_id;
export declare const Networked: typeof networked;
export declare const Reliable: typeof reliable;
export declare const Unreliable: typeof unreliable;
export declare const Pair: typeof pair;
export declare const Shared: typeof shared;

export declare class Replecs {
    server: Server;
    client: Client;

    after_replication(callback: () => void): void;
}

export declare function create_server(world?: World): Server;
export declare function create_client(world?: World): Client;
export declare function create(world?: World): Replecs;
