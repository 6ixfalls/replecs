import { World } from "@rbxts/jecs";
import { Components, Shared } from "./common";
import { Entity } from "@rbxts/jecs";

export declare class Client {
    world: World;
    inited?: boolean;
    is_replicating: boolean;
    after_replication_callbacks: Array<() => void>;

    components: Components;
    shared: Shared;
    server_ids: Map<number, Entity>;
    client_ids: Map<Entity, number>;
    ordered_creation: boolean;
    custom_ids: Map<Entity, (k: any) => Entity>;

    static create(world: World, components: Components): Client;

    init(world?: World): void;
    destroy(): void;
    after_replication(callback: () => void): void;

    apply_updates(buffer: buffer, all_variants?: Array<Array<any>>): void;
    apply_unreliable(buffer: buffer, all_variants?: Array<Array<any>>): void;
    apply_full(buffer: buffer, all_variants?: Array<Array<any>>): void;
}
