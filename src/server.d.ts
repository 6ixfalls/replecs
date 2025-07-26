import { World } from "@rbxts/jecs";
import { Components, Shared, WorldHooks } from "./common";
import { Entity } from "@rbxts/jecs";

type TrackInfo = {
    entities: Map<Entity, boolean>;
    components: Map<Entity, Map<Entity, number>>;
};

type EntityStorage = {
    tags: Map<Entity, boolean>;
    values: Map<Entity, any>;
    pairs: Map<Entity, Set<Entity>>;
};

type Storage = Map<Entity, EntityStorage>;

export declare class Server {
    world: World;
    inited?: boolean;

    static create(world: World, components: Components): Server;

    init(world?: World): void;
    destroy(): void;

    get_full(player: Player): LuaTuple<[buffer, Array<Array<any>>]>;
    collect_updates(): () => LuaTuple<[Player, buffer, Array<Array<any>>]>;
    collect_unreliable(): () => LuaTuple<[Player, buffer, Array<Array<any>>]>;
    mark_player_ready(player: Player): void;
    is_player_ready(player: Player): boolean;
}
