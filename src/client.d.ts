import { World } from "@rbxts/jecs";
import { Components } from "./common";
import { Entity } from "@rbxts/jecs";

export declare class Client {
    world: World;
    inited?: boolean;
    is_replicating: boolean;

    server_ids: Map<number, Entity>;
    client_ids: Map<Entity, number>;

    static create(world: World, components: Components): Client;

    init(world?: World): void;
    destroy(): void;
    after_replication(callback: () => void): void;

    apply_updates(buffer: buffer, all_variants?: Array<Array<any>>): void;
    apply_unreliable(buffer: buffer, all_variants?: Array<Array<any>>): void;
    apply_full(buffer: buffer, all_variants?: Array<Array<any>>): void;
}
