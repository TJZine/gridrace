import {
  type DatabaseResult,
  type Dependencies,
  type JsonObject,
} from "./command.ts";

interface RpcCall {
  name: string;
  parameters: JsonObject;
}

interface Invocation {
  request: Request;
  authenticate?: string | null;
  rpcResults?: DatabaseResult[];
}

interface Invoked {
  response: Response;
  body: JsonObject;
  rpcCalls: RpcCall[];
  authenticateCalls: number;
}

export function createCommandInvoker(
  makeHandler: (
    dependencies: Dependencies,
  ) => (request: Request) => Promise<Response>,
  userId: string,
): (invocation: Invocation) => Promise<Invoked> {
  return async (invocation) => {
    const rpcCalls: RpcCall[] = [];
    const queued = [...(invocation.rpcResults ?? [])];
    let authenticateCalls = 0;
    const dependencies: Dependencies = {
      async authenticate() {
        authenticateCalls += 1;
        const user = invocation.authenticate === undefined
          ? userId
          : invocation.authenticate;
        return await Promise.resolve(user);
      },
      createService: () => ({
        async rpc(name: string, parameters: JsonObject) {
          rpcCalls.push({ name, parameters });
          const result = queued.shift();
          if (!result) throw new Error(`unexpected RPC ${name}`);
          return await Promise.resolve(result);
        },
        deleteUser() {
          return Promise.reject(new Error("unexpected deleteUser"));
        },
      }),
    };
    const response = await makeHandler(dependencies)(invocation.request);
    return {
      response,
      body: await response.json() as JsonObject,
      rpcCalls,
      authenticateCalls,
    };
  };
}
